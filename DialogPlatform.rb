class Slot
    # name: a string that names the slot, such as 'departure city'
    # prompts: an array of possible prompts
    #    a prompt is what the system tells the user at the start of the slot
    #    such as 'Where would you like to depart from?'
    # values: an array of strings that the user can set this slot to
    #    example: ['San Diego', 'San Francisco', 'Los Angeles', 'Sacramento']
    # max_selections: the number of values a user can set at one time
    #    example: when set to 2, 'San Diego' or 'San Diego and San Francisco' are valid responses,
    #    but 'San Diego, San Francisco, and Los Angeles' is not
    # inner_slots: TODO
    def initialize(name, prompts, values, max_selections = 1, extract_threshold = 0.4, inner_slots = [])
        @name = name
        @prompts = prompts
        @values = values
        @value_dist = uniform_dist(values)
        @max_selections = max_selections
        @extract_threshold = extract_threshold
        @selections = []
        @utterance = ''
        @inner_slots = inner_slots
        @run_count = 0
        @confidence = -1
    end

    def run
        prompt
        while(true)
            @utterance = gets.chomp.downcase
            extract_selection_from_speech
            if @confidence >= @extract_threshold
                if @selections.size > @max_selections
                    too_many_response
                else
                    selection_response
                    break
                end
            elsif @confidence == 0
                puts 'TODO'
                # TODO: figure out if this is a go back command, a jump, or we have no idea what they said
            else
                clarification_prompt
                # TODO: increase probability of current selection
            end
        end
        @run_count += 1
    end

    def prompt
        puts @prompts[@run_count % @prompts.size]
    end

    # TODO: handle "yes I said that" response
    def clarification_prompt
        puts "I heard you say #{english_list(@selections)}, but I'm not sure. Could you repeat your response?"
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
    end

    # degree is a number 0 to 3 determining how much grounding to use. 0 is none, 3 is the most verbose
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
    def extract_selection_from_speech
        #TODO: probability stuff!!!
        @selections = @values.map { |value|
            phrasing = phrasings(value).find{|phrasing| @utterance[phrasing] != nil}
            value unless phrasing.nil?
        }.compact
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

    def uniform_dist(values)
        Hash[values.map{|value| [value, 1.0/values.size]}]
    end
end
