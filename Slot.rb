require './Util'
require './Input'
require './Variable'

DEBUG = false

class Slot
    # prompts: an array of possible prompts
    #    a prompt is what the system tells the user at the start of the slot
    #    such as 'Where would you like to depart from?'
    # select_threshold: number between 0 and 1, user input will be accepted if confidence is above this threshold 
    # clarify_threshold: number between 0 and 1, clarification will be requested if confidence is above this threshold 
    #    and below select_threshold. If confidence is below clarify_threshold, the run method will return false
    #    and let somebody else figure out what to do
    # utterances: array containing every utterance the user has said. An utterance is an array of Words
    def initialize(variable, prompts, select_threshold = 0.6, clarify_threshold = 0.3)
        @variable = variable
        self.prompts = prompts
        @select_threshold = select_threshold
        @clarify_threshold = clarify_threshold
        @utterances = []
        @run_count = 0
        @repetitions = 0
        @confidence = -1
    end

    def run
        @run_count += 1
        prompt
        run_cycle
    end

    def prompts=(arg)
        @prompts = arg.is_a?(Array) ? arg : [arg]
        #@prompt = @prompts.first
    end

    # TODO: make prompt follow the names example?
    def prompt
        if @prompts.is_a? Array
            puts @prompts[@run_count % @prompts.size]
        else
            puts @prompts
        end
    end

    def get_input
        p @variable.values.map{|value| [value.confidence, value]} if DEBUG
        line = gets.chomp
        utterance = Utterance.new(line)
        if utterance.find{|word| word.confidence <= 0 || word.confidence > 1}
            puts "Malformed input: Confidence should be in the range (0,1]. Please respond again."
            return get_input
        end
        return utterance
    end

    def run_cycle
        @utterances << get_input
        while(true)
            @extraction = @variable.extract(@utterances.last)
            p @extraction if DEBUG
            @selection = @variable.top_extraction(@extraction)
            @confidence = @selection.confidence
            print "Selection confidence: " if DEBUG
            p @confidence if DEBUG
            if @confidence >= @select_threshold
                break
            elsif @confidence >= @clarify_threshold
                #TODO: need to increase likelihood of all extractions, not just top
                break if did_you_say_reaction(@selection)
            else
                # returns nil so coder deccides whether to use run_clarification or do something else,
                # because maybe the user is trying to jump
                if escape(@utterances.last, @selection)
                    return nil
                else
                    extracted_nothing_reaction 
                end
            end
            @repetitions += 1
        end
        selection_reaction
        return @selection
    end

    def did_you_say_prompt
        "I didn't hear you, did you say #{Util.english_list(extraction)}?"
    end

    def did_you_say_reaction(extraction)
        puts "did you say reaction" if DEBUG
        puts apologetic(did_you_say_prompt(extraction))
        @utterances << get_input
        utterance = @utterances.last
        answer = Util.extract_yes_no(utterance)
        next_extraction = @variable.top_extraction(@variable.extract(utterance))

        # determines what selections are they trying to correct to
        selections = nil
        @confidence = 0
        if answer == 'no'
            rejection_likelihood(extraction, answer.confidence)
            if next_extraction != extraction
                selection = next_extraction
                increase_likelihood(selection)
            end
        else
            if answer == 'yes'
                selection = extraction
                confirmation_likelihood(selection, answer.confidence)
            end
            # does this comparison work?
            repetition = Extraction.new(extraction & next_extraction)
            if !repetition.empty?
                selection = repetition
                @confidence = selection.confidence * (repetition.size + 4) / (extraction.size + 4)
                confirmation_likelihood(selection, @confidence)
                # TODO: problem: say max_selection_size is 2 and Values are number in range [0,20]
                #                if they say "14" we should accept 14, rather than thinking they're also trying to do "1" and "4"
                #                however, if they say a bunch of different numbers and only one is in common, we don't want to think
                #                that we're doing well
            end
        end
        p selection if DEBUG
        print "confidence: " if DEBUG
        p @confidence if DEBUG

        # determines what to do with these selections
        if selection == nil
            puts apologetic(dont_understand_prompt)
            # TODO: slightly increase next_extractions_hash.likelihood
        else
            if @confidence >= @select_threshold
                @selection = selection
                return true
            elsif @confidence >= @clarify_threshold
                return did_you_say_reaction(selection)
            else
                puts apologetic(dont_understand_prompt)
                # TODO: slightly increase next_extractions_hash.likelihood
            end
        end
        return false
    end

    def rejection_likelihood(extraction, confidence)
        extraction.each do |value|
            #variable.prob_mass += extraction.likelihood * confidence
            value.confidence -= confidence
        end
    end

    def increase_likelihood(extraction)
        extraction.each do |value|
            #variable.prob_mass += extraction.likelihood * confidence
            value.confidence += value.confidence / 2
        end
    end

    def confirmation_likelihood(extraction, confidence)
        puts "confirmation likelihood" if DEBUG
        extraction.each do |value|
            #variable.prob_mass += extraction.likelihood * confidence
            value.confidence += value.confidence * confidence
            puts "#{value}: #{value.confidence}" if DEBUG
        end
    end

    # this is how the coder can escape the Slot, in case the user is trying to exit or jump elsewhere
    # TODO: create an example of escape in either Reservation.rb or a higher level class
    def escape(utterance, extractions)
        false
    end

    def extracted_nothing_prompt
        apologetic(dont_understand_prompt)
    end

    def dont_understand_prompt
        "I don't understand what you said."
    end

    def extracted_nothing_reaction
        extracted_nothing_prompt
        repetition_likelihood(@extraction)
        @utterances << get_input
    end

    def selection_reaction
        responses = @selection.map(&:response).compact
        responses.each{|response| puts response}
        # more succinct in following runs
        if @run_count > 1
            puts @variable.grounding(@selection, 2)
        else
            puts @variable.grounding(@selection, 1)
        end
    end

    def apologetic(prompt)
        if @repetitions < 1
            puts prompt
        else
            #puts Util.sorry_words[@repetitions % Util.sorry_words.size].capitalize + ', ' + prompt[0].downcase + prompt[1..-1]
            puts Util.sorry_words[(@repetitions - 1) % Util.sorry_words.size].capitalize + ', ' + prompt
        end
    end
end
