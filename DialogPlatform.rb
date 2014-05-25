# Prioritized TODO list

# note: there's currently an embarassing amount of duplicated code between Slot and Multislot. To some extent this is unavoidable because the functionality is similar but not identical, but when we improve code in one area we'll have to be careful to port it to the other

# to finish up the routing logic of Multislot, I need to:
# 1. write the code for handling user trying to change previous slots
# 2. debugging
# 3. cleanup variable or method names to be more clear (like extractions and selections and whether they should be plural or singular, etc)

# biggest ticket items besides the routing, which Jeremy could work on if he likes:
# 1. everything to do with probability (right now I just have arbitrary hacks, like when I want something to become more likely right now I just double the scores)
# 2. edit distance

DEBUG = true

# value: a string such as 'San Diego'
# likelihood: likelihood of this value being selected relative to other values; does not need to be a probability
# phrasings: array of regular expressions representing phrases that would indicate that the user is selecting this value
# response: response given to user if the user selects this value
# next_slot: next Slot to go to if the user selects this value
Value = Struct.new(:value, :likelihood, :phrasings, :response, :next_slot)

class Variable
    attr_accessor :name, :values, :prob_mass, :max_selection, :selection

    # name: name of the variable, such as 'departure city'
    # values: can be an array of Values, see above
    #         or it can be an array of strings such as ['San Diego', 'San Fransisco', 'Sacramento']
    #         using defaults to fill in the other fields for Values
    # prob_mass: because likelihoods don't have to be probabilities, the total probability mass may not be 1
    # max_selection: the number of values a user can set at one time
    #    example: when set to 2, 'San Diego' or 'San Diego and San Francisco' are valid responses,
    #    but 'San Diego, San Francisco, and Los Angeles' is not
    def initialize(name, values, max_selection = 1)
        @name = name
        @values = values.map {|value|
            if value.is_a?(String)
                Value.new(value, 1.0 / values.size, nil, nil, nil)
            elsif value.is_a?(Value)
                Value
            else
                raise 'Expecting a String or Value'
            end
        }
        @prob_mass = @values.map(&:likelihood).reduce(:+)
        @max_selection = max_selection
    end

    #TODO: figure out a way to never have to write value.value
    def phrasings(value)
        [/#{value.value.downcase}/]
    end

    def response
        nil
    end

    # degree is a number 0 to 3 determining how much grounding to use. 0 is none, 3 is the most verbose
    def grounding(selections, degree = 1)
        case degree
        when 1
            if selections.size <= 1
                "#{selections.first.value} was registered for the #{name}."
            else
                "#{Util.english_list(selections.map(&:value))} were registered for the #{name}."
            end
        when 2
            "#{Util.english_list(selections.map(&:value))}, #{Util.affirmation_words.sample}."
        when 3
            Util.affirmation_words.sample.capitalize + '.'
        end
    end

    def precondition
        true
    end

    def default_value
        nil
    end
end

# Every word has an associated confidence that it is what we think it is.
# Confidence must be in the range of (0, 1]
Word = Struct.new(:word, :confidence)

# An Utterance is an array of Words.
# Call line to get a string version of the utterance.
class Utterance < Array
    def line
        self.map(&:word).join(' ')
    end
end

# A Selection is an array of Values
# Confidence should be a number in (0,1]
class Selection < Array
    attr_accessor :confidence
    def initialize(array, confidence)
        @confidence = confidence
        super(array)
    end
end

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
        @variable = variable
        @prompts = prompts
        @extract_threshold = extract_threshold
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

    def prompt
        puts @prompts[@run_count % @prompts.size]
    end

# TODO: for input 'san diego (0.4)' does 0.4 apply to both words or just 'diego'? how to handle?
    def get_input
        line = gets.chomp.downcase
        Utterance.new(line.scan(/(\S+)\s?(\([\d.]+\))?/).map{|word, confidence| confidence.nil? ? Word.new(word, 1) : Word.new(word, confidence[1...-1].to_f)})
    end

    def run_cycle
        @utterances << get_input
        while(true)
            extract_selection(@utterances.last)
            if @confidence >= @extract_threshold
                break
            elsif @confidence >= @clarify_threshold
                break if did_you_say_reaction
            else
                #TODO: return false, so coder deccides whether to use run_clarification or do something else,
                # because maybe the user is trying to jump
                run_clarification
                return true
            end
            @repetitions += 1
        end
        selection_reaction
        return true
    end

    def did_you_say_prompt(extractions)
        "I didn't hear you, did you say #{Util.english_list(extractions.map(&:value))}?"
    end

    def did_you_say_reaction
        puts apologetic(@variable.did_you_say_prompt(@extractions))
        @utterances << get_input
        line = @utterances.last.line
        if Util.no_set.include? line
            repetition_likelihood(@variable.values - @extractions)
            puts "Oh, what did you mean?"
            @utterances << get_input
        elsif Util.no_set.find{|no_word| line[no_word] != nil} != nil
            repetition_likelihood(@variable.values - @extractions)
        elsif Util.yes_set.find{|no_word| line[no_word] != nil} != nil
            return true
        else
            repetition_likelihood(@extractions)
        end
        return false
    end

# TODO: make this actually good
    def repetition_likelihood(extractions)
        extractions.each{|extraction|
            @variable.prob_mass += selection.likelihood
            extraction.likelihood *= 2
        }
    end

    def clarification_prompt
        puts apologetic("I'm not sure what you said, could you repeat your response?")
    end

    def run_clarification
        clarification_prompt
        repetition_likelihood(@extractions)
        run_cycle
    end

    def selection_reaction
        responses = @extractions.map(&:response).compact
        # value specific responses
         responses.each{|response| puts response}
        # general variable response 
        puts @variable.response unless @variable.response.nil?
        # more succinct in following runs
        if @run_count > 1
            puts @variable.grounding(@extractions, 2)
        else
            puts @variable.grounding(@extractions, 1)
        end
    end

#    def too_many_response
#        puts "I was looking for at most #{max_extractions} responses, but I heard #{@extractions.size}: #{english_list(@extractions)}. Which of these would you like?"
        #change probabilities

    # returns 0 if it couldn't find anything at all,
    # otherwise returns confidence probability
    def extract_selection(utterance)
# TODO: use edit distance
        line = utterance.line
        extractions = @variable.values.map { |value|
            phrasings = value.phrasings.nil? ? @variable.phrasings(value) : value.phrasings
            phrasing_index = phrasings.find_index{|phrasing| line[phrasing] != nil}
            [value, phrasing_index] unless phrasing_index.nil?
        }.compact
# orders the extractions by probability, then by most recently said in utterance
        extractions.sort{|a, b|
            first_order = b[0].likelihood <=> a[0].likelihood
            first_order == 0 ? b[1] <=> b[1] : first_order
        }
        @extractions = extractions.map{|value, phrasing_index| value}.first @variable.max_selection
        if @extractions.size == 0
            @confidence = 0
        else
            @confidence = calc_confidence
        end
        puts "(DEBUG) confidence: " + @confidence.to_s if DEBUG
    end

# BIGGEST TODO: use probabilities to get confidence, right now I've just got a mind boggling stupid hack
    def calc_confidence(utterance, extractions)
        confidence = utterance.map(&:confidence).reduce(:+) / utterance.size
        (confidence + extractions.first.likelihood) / 2
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

class Util
    # returns 'green, purple, and red' for ['green', 'purple', 'red']
    def self.english_list(list)
        if list.size == 0
            'nothing'
        elsif list.size == 1
            list.first
        else
            list[0...-1].join(', ') + ' and ' + list[-1]
        end
    end

    def self.affirmation_words
        ['okay', 'alright', 'sure', 'cool']
    end

    def self.sorry_words
        ['sorry', 'apologies', 'excuse me', 'truly sorry', 'my apologies', 'pardon me', 'my sincerest apologies', 'begging forgiveness']
    end

    def self.yes_set
        ['yes', 'yep', 'yeah', 'yea', 'aye', 'affirmative', 'definitely', 'certainly', 'positively']
    end

    def self.no_set
        ['no', 'nope', 'nah', 'nay', 'negative', 'nix', 'never', 'not at all', 'not in the slightest', 'not by any means']
    end
end

# TODO: when extracting multiple slots at a time, need to ignore overlapped values. e.g.:
# say cities for departure and destination are the same, and say
# the phrasings for destination are   [/#{value}/, /from #{value}/]
# and the phrasings for departure are [/#{value}/, /to #{value}/]
# we ignore instances of /#{value}/ completely and only look for the ones with 'from' or 'to'
# and if it doesn't find anything, have a special disambiguation_response

# Prompts for more than one piece of information at a time
class MultiSlot
    # extractions refer to any possible selection of values we think the user might be making from their utterance
    # selections refer to extractions that we believe are true
    # both are hashes from Variable to Selection
    def initialize(variables, prompts, variables_needed = variables, extract_threshold = 0.6, clarify_threshold = 0.3, change_threshold = 0.6)
        @variables = variables
        @prompts = prompts
        @extract_threshold = extract_threshold
        @clarify_threshold = clarify_threshold
        @change_threshold = change_threshold
        @utterances = []
        @run_count = 0
        @selections = {}
        @variables_needed = variables_needed
    end

    # not intended for overwrite, just here for convenience
    def @remaining_needed_vars
        @variables_needed - @selections.keys
    end

    # not intended for overwrite, just here for convenience
    def @remaining_vars
        @variables - @selection.keys
    end

    def run
        @run_count += 1
        prompt
        run_cycle
    end

    def prompt
        puts @prompts[@run_count % @prompts.size]
    end

# TODO: for input 'san diego (0.4)' does 0.4 apply to both words or just 'diego'? how to handle?
    def get_input
        line = gets.chomp.downcase
        line.scan(/(\S+)\s?(\([\d.]+\))?/).map{|word, confidence| confidence.nil? ? Word.new(word, 1) : Word.new(word, confidence[1...-1].to_f)}
    end

    def run_cycle
        @utterances << get_input
        while(true)
            extracted = 0
            @extractions = {}
            extracted_something = false
            @variables.each {|variable|
                extract_selection(@utterances.last, variable)
                selections = @selections[variable]
                extractions = @extractions[variable]
                if extractions.confidence > @extract_threshold
                    if selections.nil?
                        @selections[variable] = extractions
                        extracted_something = true
                        selection_reaction(variable, extractions)
                    elsif extractions.confidence > selections.confidence
                        replace_response(selections, extractions, variable)
                        @selections[variable] = extractions
                        extracted_something = true
                    end
                end
            }
            if false
# check for change (change____var name: value), if accept, ask for confirmation, if yes change it, if no reduce likelihood
# also: handle "Flying on the 17th and change my destinatino to San Diego"?
            else
                if @remaining_needed_vars.empty?
                    break
                elsif extracted_something
                    remaining_vars_prompt
                    @utterances << get_input
                else
                    best_extraction = @extractions.values.reduce{|a,b| a.confidence > b.confidence ? a : b}
                    if best_extraction.confidence >= clarify_threshold
                        break if did_you_say_reaction(best_extraction)
                    else
                        extracted_nothing_prompt
                        @utterances << get_input
                    end
                end
            end
            @repetitions += 1
        end
        final_selection_reaction
        return true
    end

    def extract_selection(utterance, variable)
# TODO: use edit distance
        line = utterance.line
        extractions = variable.values.map { |value|
            phrasings = value.phrasings.nil? ? variable.phrasings(value) : value.phrasings
            phrasing_index = phrasings.find_index{|phrasing| line[phrasing] != nil}
            [value, phrasing_index] unless phrasing_index.nil?
        }.compact
# orders the extractions by probability, then by most recently said in utterance
        extractions.sort{|a, b|
            first_order = b[0].likelihood <=> a[0].likelihood
            first_order == 0 ? b[1] <=> b[1] : first_order
        }
        extractions = extractions.map{|value, phrasing_index| value}.first variable.max_selection
        if extractions.size == 0
            confidence = 0
        else
            confidence= calc_confidence
        end
        @extractions[variable] = Selection.new(extractions, confidence)
        puts "(DEBUG) confidence: " + @confidence[variable].to_s if DEBUG
    end

    def remaining_vars_prompt
        puts "What is your #{english_list(remaining_vars.map(&:name))}?"
    end

    def extracted_nothing_prompt
        puts apologetic("I didn't understand.")
        remaining_vars_prompt
    end

# BIGGEST TODO: use probabilities to get confidence, right now I've just got a mind boggling stupid hack
    def calc_confidence(utterance, extractions)
        confidence = utterance.map(&:confidence).reduce(:+) / utterance.size
        (confidence[variable] + extractions[variable].first.likelihood) / 2
    end

    def replace_response(old_selections, new_selections, variable)
# TODO
    end

    def final_selection_reaction
# TODO: change this to be more succinct, i.e. "Okay, this this and that were registered for this this and that"
# currently it's more of a placeholder that's redundant with the selection_reactions during the dialog
        @variables.each {|variable|
            if @extractions[variable].nil?
                #an unneeded and unanswered variable uses its default value if it has one
                selection_reaction(variable, variable.default_value) unless variable.default_value.nil?
            else
                selection_reaction(variable, @extractions[variable])
            end
        }
    end

    def selection_reaction(variable, value)
        responses = @extractions.map(&:response).compact
        # value specific responses
         responses.each{|response| puts response}
        # general variable response 
        puts @variable.response unless @variable.response.nil?
        # more succinct in following runs
        if @run_count > 1
            puts @variable.grounding(@extractions, 2)
        else
            puts @variable.grounding(@extractions, 1)
        end
    end

    def did_you_say_prompt(extractions)
        "I didn't hear you, did you say #{Util.english_list(extractions.map(&:value))}?"
    end

    def did_you_say_reaction(extractions)
        puts apologetic(@variable.did_you_say_prompt(extractions))
        @utterances << get_input
        line = @utterances.last.line
        if Util.no_set.include? line
            repetition_likelihood(@variable.values - extractions)
            puts "Oh, what did you mean?"
            @utterances << get_input
        elsif Util.no_set.find{|no_word| line[no_word] != nil} != nil
            repetition_likelihood(@variable.values - @extractions)
        elsif Util.yes_set.find{|no_word| line[no_word] != nil} != nil
            return true
        else
            repetition_likelihood(extractions)
        end
        return false
    end

# TODO: make this actually good
    def repetition_likelihood(extractions)
        extractions.each{|extraction|
            @variable.prob_mass += selection.likelihood
            extraction.likelihood *= 2
        }
    end

    # degree is a number 0 to 3 determining how much grounding to use. 0 is none, 3 is the most verbose
    # TODO: change selections so it's the multislot hash version
    def grounding(selections, degree = 1)
        case degree
        when 1
            if selections.size <= 1
                "#{selections.first.value} was registered for the #{name}."
            else
                "#{Util.english_list(selections.map(&:value))} were registered for the #{name}."
            end
        when 2
            "#{Util.english_list(selections.map(&:value))}, #{Util.affirmation_words.sample}."
        when 3
            Util.affirmation_words.sample.capitalize + '.'
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

# class SlotGroup ?
# is there a need for a tree class or will that just fall out of how you write it?
