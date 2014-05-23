# value: a string such as 'San Diego'
# likelihood: likelihood of this value being selected relative to other values; does not need to be a probability
# phrasings: array of regular expressions representing phrases that would indicate that the user is selecting this value
# response: response given to user if the user selects this value
# next_slot: next Slot to go to if the user selects this value
Value = Struct.new(:value, :likelihood, :phrasings, :response, :next_slot)

class Variable
    # name: name of the variable, such as 'departure city'
    # values: can be an array of Values, see above
    #         or it can be an array of strings such as ['San Diego', 'San Fransisco', 'Sacramento']
    #         using defaults to fill in the other fields for Values
    # prob_mass: because likelihoods don't have to be probabilities, the total probability mass may not be 1
    # max_selection: the number of values a user can set at one time
    #    example: when set to 2, 'San Diego' or 'San Diego and San Francisco' are valid responses,
    #    but 'San Diego, San Francisco, and Los Angeles' is not
    # selection: what the user actual selects. Can be a Value or an Array of Values
    def initialize(name, values, max_selection = 1)
        @name = name
        @values = values.map {|value|
            if value.is_a?(String)
                Value.new(value, 1.0 / values.size, [/#{value.downcase}/], nil, nil)
            elsif value.is_a?(Value)
                Value
            else
                raise 'Expecting a String or Value'
            end
        }
        @prob_mass = @values.map(&:likelihood).reduce(:+)
        @max_selection = max_selection
        @selection = nil
    end

    def values
        @values
    end

    def name
        @name
    end

    def prob_mass
        @prob_mass
    end

    def max_selection
        @max_selection
    end

    def precondition
        return true
    end
end

# Every word has an associated confidence that it is what we think it is.
# Confidence must be in the range of (0, 1]
Word = Struct.new(:word, :confidence)

class Slot
    # prompts: an array of possible prompts
    #    a prompt is what the system tells the user at the start of the slot
    #    such as 'Where would you like to depart from?'
    # extract_threshold: number between 0 and 1, user input will be accepted if confidence is above this threshold 
    # clarify_threshold: number between 0 and 1, clarification will be requested if confidence is above this threshold 
    #    and below extract_threshold. If confidence is below clarify_threshold, the run method will return false
    #    and let somebody else figure out what to do
    # utterances: array containing every utterance the user has said. An utterance is an array of Words
    def initialize(variable, prompts, extract_threshold = 0.6, clarify_threshold = 0.3)
        @name = variable.name
        @values = variable.values
        @prob_mass = variable.prob_mass
        @max_selection = variable.max_selection
        @prompts = prompts
        @extract_threshold = extract_threshold
        @clarify_threshold = clarify_threshold
# TODO: clean up this having to do .map(&:word).join(' ') business
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

# TODO: for input 'san diego (0.4)' does 0.4 apply to both words or just 'diego'? how to handle?
    def get_input
        line = gets.chomp.downcase
        line.scan(/(\S+)\s?(\([\d.]+\))?/).map{|word, confidence| confidence.nil? ? Word.new(word, 1) : Word.new(word, confidence[1...-1].to_f)}
    end

    def run_cycle
        @utterances << get_input
        while(true)
            extract_selection(@utterances.last)
            if @confidence >= @extract_threshold
                selection_reaction
                break
            elsif @confidence >= @clarify_threshold
                return true if did_you_say_reaction
            else
                #TODO: return false
                run_clarification
                return true
            end
            @repetitions += 1
        end
        return true
    end

    def prompt
        puts @prompts[@run_count % @prompts.size]
    end

    def apologetic(prompt)
        #puts sorry_words[@repetitions % sorry_words.size].capitalize + ', ' + prompt[0].downcase + prompt[1..-1]
        puts sorry_words[@repetitions % sorry_words.size].capitalize + ', ' + prompt
    end

    def did_you_say_reaction
        puts apologetic("I didn't hear you, did you say #{english_list(@selections.map(&:value))}?")
        old_selections = @selections
        @utterances << get_input
        line = @utterances.last.map(&:word).join(' ')
        if no_set.include? line
            repetition_likelihood(@values - @selections)
            puts "Oh, what did you mean?"
            @utterances << get_input
        elsif no_set.find{|no_word| line[no_word] != nil} != nil
            repetition_likelihood(@values - @selections)
        elsif yes_set.find{|no_word| line[no_word] != nil} != nil
            return true
        else
            repetition_likelihood(@selections)
        end
        return false
    end

    def run_clarification
        puts apologetic("I'm not sure what you said, could you repeat your response?")
        repetition_likelihood(@selections)
        run_cycle
    end

    def repetition_likelihood(selections)
        selections.each{|selection|
            @prob_mass += selection.likelihood
            selection.likelihood *= 2
        }
    end

    def selection_reaction
        @selections.each{|selection| puts selection.response}
        if @run_count > 1
            puts grounding(2)
        else
            puts grounding(1)
        end
    end

#    def too_many_response
#        puts "I was looking for at most #{max_selections} responses, but I heard #{@selections.size}: #{english_list(@selections)}. Which of these would you like?"
        #change probabilities
#    end

    # degree is a number 0 to 3 determining how much grounding to use. 0 is none, 3 is the most verbose
# rename acknowledgement_grounding?
    def grounding(degree)
        case degree
        when 1
            if @selections.size <= 1
                "#{@selections.first.value} was registered for the #{@name}."
            else
                "#{english_list(@selections.map(&:value))} were registered for the #{@name}."
            end
        when 2
            "#{english_list(@selections.map(&:value))}, #{affirmation_words.sample}."
        when 3
            affirmation_words.sample.capitalize + '.'
        end
    end

    def affirmation_words
        ['okay', 'alright', 'sure', 'cool']
    end

    def sorry_words
        ['sorry', 'apologies', 'excuse me', 'truly sorry', 'my apologies', 'pardon me', 'my sincerest apologies', 'begging forgiveness']
    end

    # returns 'green, purple, and red' for ['green', 'purple', 'red']
    def english_list(list)
        if list.size == 0
            'nothing'
        elsif list.size == 1
            list.first
        else
            list[0...-1].join(', ') + ' and ' + list[-1]
        end
    end

    # returns 0 if it couldn't find anything at all,
    # otherwise returns confidence probability
    def extract_selection(utterance)
# TODO: use edit distance
        line = utterance.map(&:word).join(' ')
        selections = @values.map { |value|
            phrasing_index = value.phrasings.find_index{|phrasing| line[phrasing] != nil}
            [value, phrasing_index] unless phrasing_index.nil?
        }.compact
# orders the selections by probability, then by most recently said in utterance
        selections.sort{|a, b|
            first_order = b[0].likelihood <=> a[0].likelihood
            first_order == 0 ? b[1] <=> b[1] : first_order
        }
        @selections = selections.map{|value, phrasing_index| value}.first @max_selection
# BIGGEST TODO: use probabilities to get confidence, right now I've just got a mind boggling stupid hack
        if @selections.size == 0
            @confidence = 0
        else
            @confidence = utterance.map(&:confidence).reduce(:+) / utterance.size
            @confidence = (@confidence + @selections.first.likelihood) / 2
        end
        puts "hey " + @confidence.to_s
    end

    def yes_set
        ['yes', 'yep', 'yeah', 'yea', 'aye', 'affirmative', 'definitely', 'certainly', 'positively']
    end

    def no_set
        ['no', 'nope', 'nah', 'nay', 'negative', 'nix', 'never', 'not at all', 'not in the slightest', 'not by any means']
    end
end

# TODO: when extracting multiple slots at a time, need to ignore overlapped values. e.g.:
# say cities for departure and destination are the same, and say
# the phrasings for destination are   [/#{value}/, /from #{value}/]
# and the phrasings for departure are [/#{value}/, /to #{value}/]
# we ignore instances of /#{value}/ completely and only look for the ones with 'from' or 'to'
# and if it doesn't find anything, have a special disambiguation_response

class MultiSlot
    def initialize(variables, prompts, extract_threshold = 0.6, clarify_threshold = 0.3)
        @variables = variables
        @prompts = prompts
        @extract_threshold = extract_threshold
        @clarify_threshold = clarify_threshold
        @utterances = []
        @run_count = 0
        @confidence = -1
    end
end
