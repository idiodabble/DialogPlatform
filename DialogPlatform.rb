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
        @prob_mass = value.map(&:likelihood).reduce(:+)
        @max_selection = max_selection
        @selection = nil
    end

    def values
        @values
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
        prompt
        run_helper
        @run_count += 1
    end

    def parse_input(line)
        line.scan(/(\S+)\s?(\([\d.]+\))?/).map{|word, confidence| confidence.nil? ? Word.new(word, 1) : Word.new(word, confidence[1...-1])}
    end

    def run_helper
        while(true)
            @utterances << parse_input(gets.chomp.downcase)
            extract_selection(@utterances.last)
            if @confidence >= @extract_threshold
                if @selections.size > @max_selections
                    too_many_response
                else
                    selection_response
                    break
                end
            elsif @confidence >= @clarify_threshold
                did_you_mean_prompt
#TODO allow changing behavior with repeated did-you-means
            else
                return false
            end
            @repetitions += 1
        end
        return true
    end

    def prompt
        puts @prompts[@run_count % @prompts.size]
    end

# good name?
    def apologetic_grounding
    end

    def did_you_mean_prompt
#TODO: make more apologetic with further did_you_mean_count
        puts "I'm not sure what you said, did you mean #{english_list(@selections)}?"
        old_selections = @selections
        @utterance = gets.chomp.downcase
        if Utility.no_set.include? @utterance
        puts "Oh, what did you mean?"
# if one selection, set pr to zero, otherwise do the inverse selection repetition likelihood trick
#TODO: how to send back to run_helper?
        elsif Utility.no_set.find{|no_word| @utterance[no_word] != nil} != nil
            @selections = @values - @selections
            repetition_likelihood
#TODO: how to send back to run_helper?
        elsif Utility.yes_set.find{|no_word| @utterance[no_word] != nil} != nil
            return true
        else
            repetition_likelihood
#TODO: how to send back to run_helper?
        end
    end

    def run_clarification
        puts "I'm not sure what you said, could you repeat your response?"
        repetition_likelihood
        run_helper
    end

    def repetition_likelihood
        @selections.each{|selection|
            @value_distr_mass += @value_distr[selection]
            @value_distr[selection] *= 2
        }
    end

    def selection_response
        if false #@confidence > 0.5 + @extract_threshold/2
            puts grounding(2)
        else
            puts grounding(1)
        end
    end

    def too_many_response
        puts "I was looking for at most #{max_selections} responses, but I heard #{@selections.size}: #{english_list(@selections)}. Which of these would you like?"
        #TODO: change probabilities
    end

    # degree is a number 0 to 3 determining how much grounding to use. 0 is none, 3 is the most verbose
# rename acknowledgement_grounding?
    def grounding(degree)
        case degree
        when 1
            if @selections.size <= 1
                "#{@selections.first} was registered for the #{@name}."
            else
                "#{english_list(@selections)} were registered for the #{@name}."
            end
        when 2
            "#{english_list(@selections)}, #{affirmation_words.sample}."
        when 3
            affirmation_words.sample.capitalize + '.'
        end
    end

    def affirmation_words
        ['okay', 'alright', 'sure', 'cool']
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
        @selections = @values.map { |value|
            phrasing = phrasings(value).find{|phrasing| utterance[phrasing] != nil}
            value unless phrasing.nil?
        }.compact
# TODO: order the selections by probability, then order by most recently said in utterance
# then return just the top max_selections
# QUESTION: this would mean it would never go to too_many_response... ???
# TODO: make confidence
        @confidence = @selections.size == 0 ? 0 : 1
    end

# TODO: when extracting multiple slots at a time, need to ignore overlapped values. e.g.:
# say cities for departure and destination are the same, and say
# the phrasings for destination are   [/#{value}/, /from #{value}/]
# and the phrasings for departure are [/#{value}/, /to #{value}/]
# we ignore instances of /#{value}/ completely and only look for the ones with 'from' or 'to'
# and if it doesn't find anything, have a special disambiguation_response

    # returns an array of regexes representing possible ways to phrase the value, i.e.
    #    [/to #{value}/, /(land)|(landing) in #{value}/, /(arrive)|(arriving) (in)|(at) #{value}/]
    def phrasings(value)
        [/#{value.downcase}/]
    end

    def uniform_distr(values)
        #Hash[values.map{|value| [value, 1.0/values.size]}]
        Hash[values.map{|value| [value, 1.0]}]
    end
end

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

class Utility
#TODO: numbers

    def yes_set
        ['yes', 'yep', 'yeah', 'yea', 'aye', 'affirmative', 'definitely', 'certainly', 'positively']
    end

    def no_set
        ['no', 'nope', 'nah', 'nay', 'negative', 'nix', 'never', 'not at all', 'not in the slightest', 'not by any means']
    end
end
