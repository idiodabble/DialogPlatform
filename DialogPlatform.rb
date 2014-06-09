# Designed to let users easily make new dialog systems with a platform that is heavily modifiable, so it can be customized to the individual dialog system's needs.
# Author:: Daniel Steffee and Jeremy Hines

# Jeremy TODO LIST:

# 1. Bug:
    # In the time MultiSlot in Reservations, if you say
    # - January 2014
    # - No
    # - Afternoon of the 21st
    # - 21st
    # It sets 2 for the day instead of 21

    # also, maybe the same bug: why does it think I'm choosing 14 for my day when I type "January 7, 2014"? Shouldn't 7, an exact match, be better than 2014?

# 2. Treat San (0.1) Diego (0.1) differently from San (1) Diego (1)
# 3. Add synonyms
# 4. Write MultiSlot version of extract, which needs to detect overlaps (same values in different variables)

# also, do multi-word prefixes work?

# Steff TODO list:

# 1. Finish testing did_you_say_reaction, then port everything over to change_reaction
# 2. test MultiSlot with variables with max_selections higher than 1
# 3. create a default variable_name prefix of some sort

# 4. change the rejection/confirmation/increase likelihood methods?
# 5. maybe replace @name_thresholds with name_threshold() methods?

# Bonus TODO list for if we have time:

# 1. Make a proper RDOC. For now, the description of the system in the writeup + comments should be enough
# 2. write a Platform class, higher than Slot or MultiSlot, that will take advantage of methods like preconditions and next_slot
# 3. be able to look up things and give the user options, i.e. "There are no flights at this time" or "We have flights available for $500, $400 and $300"

DEBUG = true

class Value < String
    attr_accessor :prior, :confidence, :phrasings, :response, :next_slot, :prefixes, :suffixes, :synonyms
    
    # Params:
    # +name+:: a string such as 'San Francisco'
    # +prior+:: prior probability of this value being selected, e.g. "San Francisco" having 0.3 and "San Diego" having 0.2 because SFO is more popular; must be a number in (0,1)
    # +confidence+:: confidence that this value is being selected by the user; must be a number but does not have to be a probability
    # +prefixes+:: words that we might expect to see before the value, e.g. "from" or "to"
    # +suffixes+:: words that we might expect to see after the value, e.g. "airport"
    # +synonyms+:: words that we might expect in place of the value, e.g. "San Fran"
    # +response+:: response given to user if the user selects this value
    # +next_slot+:: next Slot to go to if the user selects this value
    def initialize(name, prior, confidence = prior, prefixes = [], suffixes = [], synonyms = [], response = nil, next_slot = nil)
        @prior = prior; @confidence = confidence; @prefixes = prefixes; @suffixes = suffixes; @synonyms = synonyms; @response = response; @next_slot = next_slot
        super(name)
    end
end

#
class Variable
    attr_accessor :name, :values, :max_selection_size, :selection, :prefixes, :suffixes

    # Params:
    # +name+:: name of the variable, such as 'departure city'
    # +values+:: can be an array of Values, see above
    #         or it can be an array of strings such as ['San Diego', 'San Fransisco', 'Sacramento']
    #         using defaults to fill in the other fields for Values
    # +prob_mass+:: because confidences don't have to be probabilities, the total probability mass may not be 1
    # +max_selection_size+:: the number of values a user can set at one time
    #    example: when set to 2, 'San Diego' or 'San Diego and San Francisco' are valid responses,
    #    but 'San Diego, San Francisco, and Los Angeles' is not
    # +prefixes+:: words that we might expect to see before a value, e.g. "from" or "to"
    # +suffixes+:: words that we might expect to see after a value, e.g. "airport"
    def initialize(name, values, max_selection_size = 1, prefixes = [], suffixes = [])
        @name = name
        @values = values.map {|value|
            if value.is_a?(String)
                Value.new(value, 1.0 / values.size)
            elsif value.is_a?(Value)
                Value
            else
                raise 'Expecting a String or Value'
            end
        }
        @max_selection_size = max_selection_size
        @prefixes = prefixes
        @suffixes = suffixes
    end

    def prob_mass
        @values.map(&:confidence).reduce(:+)
    end

    # degree is a number 0 to 3 determining how much grounding to use. 0 is none, 3 is the most verbose
    def grounding(selections, degree = 1)
        case degree
        when 1
            if selections.size <= 1
                "#{selections.first} was registered for the #{name}."
            else
                "#{Util.english_list(selections)} were registered for the #{name}."
            end
        when 1.5
            if selections.size <= 1
                "#{selections.first} was set for the #{name}."
            else
                "#{Util.english_list(selections)} were set for the #{name}."
            end
        when 2
            "#{Util.english_list(selections)}, #{Util.affirmation_words.sample}."
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

    def did_you_say_prompt(extraction)
        "I didn't hear you, did you say #{Util.english_list(extraction)}?"
    end

    def prefixes=(arr)
        if(arr.kind_of?(Array)) then
            @prefixes = arr
        elsif(arr.kind_of?(String)) then
            @prefixes = [arr]
        else
            p "ERROR, Prefixes are not in usable form."
        end
    end

    def suffixes=(arr)
        if(arr.kind_of?(Array)) then
            @suffixes = arr
        elsif(arr.kind_of?(String)) then
            @suffixes = [arr]
        else
            p "ERROR, Suffixes are not in usable form."
        end
    end

    # return array of hash of value, confidence and position
    def extract(utterance)
        puts @name if DEBUG
        puts "(DEBUG) utterance: " if DEBUG
        p utterance if DEBUG
        extraction = Extraction.new

        @values.each do |value|
            confidence = calc_confidence(utterance, value)
            #value.confidence = confidence * confidence.abs
            value.confidence = (value.confidence + 2 * confidence) / 3 unless confidence == 0
            puts "(DEBUG) value: #{value} confidence: #{confidence} new value confidence: #{value.confidence}" if DEBUG
            extraction << value
        end
        #scores_to_prob(extractions)
        #puts "(DEBUG) extractions: " + extractions.to_s if DEBUG
        return extraction
    end

    # given an utterance (which is an array of Word, with the .line method to get rid of parenthetical likelihoods)
    # and given all the fields in this Variable class, such as @values
    # return a list of all the values and your confidence that the user is trying to select them, for example:
    # {"San Diego" => 0.8, "San Francisco" => 0.2, "Los Angeles" => 0}
    # or however you want to organize it
    # also, keep in mind that every Word has an associated likelihood, and same goes for every Value
    # words = Util.get_words_from_phrasing(utterance, phrasing)
    # min_conf = words.map(&:confidence).min
    # TODO do something smarter
    # min_conf * value.likelihood * @values.size

    def calc_confidence(utterance, value)
        phrasings = get_possible_phrasings(utterance, value)
        # p "phrasings", phrasings if DEBUG
        max_score = 0
        phrasings.each do |phrase|
            score = 0
            phrase_len = phrase.length
            (1..utterance.length).each do |num_words|
                (0..(utterance.length - num_words)).each do |start_index|
                    sub_str = utterance.select_slice(start_index, start_index + num_words)
                    score = edit_distance(sub_str, phrase)
                    # p "score", score, "phrase", phrase, "value", value
                    max_score = [max_score, score].max
                end
            end
        end
        max_score
    end

    # Checks input for possible phrasings for the input
    def get_possible_phrasings(utterance, value)
        #p "line", line, "value", value if DEBUG
        valid_phrasings = [value]
        prefixes = @prefixes.concat value.prefixes
        suffixes = @suffixes.concat value.suffixes
        prefixes.each do |pre|
            utterance.each do |word|
                if word == pre
                    valid_phrasings << (pre + ' ' + value)
                end
            end
        end
        suffixes.each do |suf|
            utterance.each do |word|
                if word == suf
                    valid_phrasings << (value + ' ' + suf)
                end
            end
        end
        valid_phrasings
    end

    def edit_distance(sub_str, phrasing)
        l = sub_str.downcase
        p = phrasing.downcase
        l_len = sub_str.length
        p_len = phrasing.length
        return p_len if (l_len == 0 or p_len == 0)
        m = Array.new(l_len + 1) {Array.new(p_len + 1)}

        (0..l_len).each {|i| m[i][0] = i}
        (0..p_len).each {|j| m[0][j] = j}
        (1..p_len).each do |j|
            (1..l_len).each do |i|
                m[i][j] = if l[i-1] == p[j-1]  # adjust index into string
                    m[i-1][j-1]       # no operation required
                else
                    [
                        m[i-1][j]+1,    # deletion
                        m[i][j-1]+1,    # insertion
                        m[i-1][j-1]+2  # substitution
                    ].min
                end
            end
        end
        len = [l_len, p_len].max
        1 - (m[l_len][p_len].to_f/len)
    end

    def scores_to_prob(extraction)
        sum = 0
        extraction.each do |value|
            sum = sum + value.confidence
        end
        return if sum == 0
        extraction.each do |value|
            value.confidence /= sum
        end
    end

    def top_extraction(extraction)
        Extraction.new(extraction.sort{|a, b|
            first_order = b.confidence <=> a.confidence
            #first_order == 0 ? b[:position] <=> a[:position] : first_order
        }.first @max_selection_size)
    end
end

# Every word has an associated confidence that it is what we think it is.
# Confidence must be in the range of (0, 1]
class Word < String
    attr_accessor :confidence
    def initialize(word, confidence)
        @confidence = confidence
        super(word)
    end
end

# An Utterance is an array of Words.
# Call line to get a string version of the utterance.
class Utterance < Array
    def line
        self.join(' ')
    end

    def select_slice(start, length)
        sliced = self.slice(start, length)
        sliced.join(' ')
    end
end

# An Extraction is an Array of Value
class Extraction < Array
    def confidence
        self.map(&:confidence).min
    end
end

# A Selection is an array of Values
# Confidence should be a number in (0,1]
# class Selection < Array
 #   attr_accessor :confidence
 #   def initialize(array, confidence)
 #       @confidence = confidence
 #       super(array)
 #   end
#end

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
        @prompts = prompts
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

    def prompt
        if @prompts.is_a? Array
            puts @prompts[@run_count % @prompts.size]
        else
            puts @prompts
        end
    end

    def get_input
        p @variable.values.map{|value| [value.confidence, value]} if DEBUG
        line = gets.chomp.downcase
        
        utterance = Utterance.new(line.scan(/([\w'-]+)[\.\?!,]?\s?(\([\+-]?[\d.]+\))?/).map{|word, confidence| confidence.nil? ? Word.new(word, 1.0) : Word.new(word, confidence[1...-1].to_f)})
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

    def did_you_say_reaction(extraction)
        puts "did you say reaction" if DEBUG
        puts apologetic(@variable.did_you_say_prompt(extraction))
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
p "yo"
p extraction
p next_extraction
            repetition = Extraction.new(extraction & next_extraction)
            p repetition
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
            p value
            p confidence
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
        extraction.each do |value|
            #variable.prob_mass += extraction.likelihood * confidence
            p value.confidence
            value.confidence += value.confidence * confidence
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

    # sets @extractions, @selections and @confidence
    # returns 0 if it couldn't find anything at all,
    # otherwise returns confidence probability
    #def extract(utterance)
    #    if @extraction.size == 0
    #        @confidence = 0
    #    else
    #        @confidence = calc_confidence(@selection)
    #    end
        #puts "(DEBUG) confidence: " + @confidence.to_s if DEBUG
    #end

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
    def self.extract_yes_no(utterance)
        if utterance.size == 1
            word = utterance.first
            if Util.no_set.include? word
                return Value.new('no', word.confidence) 
            elsif Util.yes_set.include? word
                return Value.new('yes', word.confidence)
            end
        end
        no = utterance.find{|word| Util.no_set.include? word}
        yes = utterance.find{|word| Util.yes_set.include? word}
        if no && yes.nil?
            return Value.new('no', no.confidence / utterance.size)
        elsif no.nil? && yes
            return Value.new('yes', yes.confidence / utterance.size)
        end
        return Value.new('not found', 0)
    end

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

    # Tries to get which Words are relevant to a phrasing
    # by looking at the start and end of the regex match
    def self.get_words_from_phrasing(utterance, phrasing)
        match = phrasing.match(utterance.line)
        start_pos = match.begin(0)
        end_pos = match.end(0)
        words = []
        utterance.reduce(0){|sum,n| words << [n, sum]; sum + n.length + 1}
        words.select{|word| start_pos <= word[1] && word[1] < end_pos}.map{|word| word[0]}
    end

    def self.affirmation_words
        ['okay', 'alright', 'sure', 'cool']
    end

    def self.sorry_words
        ['sorry', 'apologies', 'excuse me', 'truly sorry', 'my apologies', 'pardon me', 'my sincerest apologies', 'begging forgiveness']
    end

    def self.yes_set
        ['yes', 'yep', 'yeah', 'yea', 'aye']
    end

    def self.certain_set
        ['definitely', 'certainly', 'absolutely', 'positively']
    end

    # Note: 'not' is definitely not the same as 'no', but it often works out the same
    def self.no_set
        ['no', 'nope', 'nah', 'nay', 'negative', 'nix', 'never', 'not']
    end

    def self.amplifier_set
        ['really', 'very', 'quite', 'extremely', 'abundantly', 'copiously']
    end

    def self.change_set
        ['change', 'actually', 'replace', 'switch', 'swap']
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
    def initialize(variables, prompts, variables_needed = variables, select_threshold = 0.6, clarify_threshold = 0.3, change_threshold = 0.6)
        @variables = variables
        @prompts = prompts
        @select_threshold = select_threshold
        @clarify_threshold = clarify_threshold
        @change_threshold = change_threshold
        @utterances = []
        @run_count = 0
        @apologies = 0
        @selections = {}
        @variables_needed = variables_needed
    end

    # not intended for overwrite, just here for convenience
    def remaining_vars_needed
        @variables_needed - @selections.keys
    end

    # not intended for overwrite, just here for convenience
    def remaining_vars
        @variables - @selections.keys
    end

    def run
        @run_count += 1
        @run_cycles = 0
        prompt
        run_cycle
    end

    def prompt
        if @prompts.is_a? Array
            puts @prompts[@run_count % @prompts.size]
        else
            puts @prompts
        end
    end

    def get_input
        #p @variables.map{|var| var.values.map{|val| p [val, val.confidence]}} if DEBUG
        line = gets.chomp.downcase
        utterance = Utterance.new(line.scan(/([\w'-]+)[\.\?!,]?\s?(\([\+-]?[\d.]+\))?/).map{|word, confidence| confidence.nil? ? Word.new(word, 1.0) : Word.new(word, confidence[1...-1].to_f)})
        if utterance.find{|word| word.confidence <= 0 || word.confidence > 1}
            puts "Malformed input: Confidence should be in the range (0,1]. Please respond again."
            return get_input
        end
        return utterance
    end

# is there a need for different thresholds for different variables?

# first, extract stuff
# if there were successful extractions, ground them
# then, if it looks like they're trying to replace (past change_threshold), do replace reaction
# else, if there's anything in the extract to clarify_threshold range, do did_you_say reaction
# else, if there were no extractions and it looks like they're trying to escape (past escape_threshold?), do escape
# else, if there were no extractions, do extracted_nothing reaction
    def run_cycle
        @reprompt = false
        while(!remaining_vars_needed.empty?)
            @run_cycles += 1
            puts remaining_vars_prompt if @reprompt
            @reprompt = true
            @utterances << get_input
            utterance = @utterances.last

            extractions = extract(utterance, remaining_vars)
            confident_hash = extractions.select{|var, extractions| extractions.confidence >= @select_threshold}
            change_hash = simpler_group(extract_change(utterance, @selections.keys))
            maybe_hash = extractions.select{|var, extractions| extractions.confidence < @select_threshold && extractions.confidence >= @clarify_threshold}

            selection_reaction(confident_hash) unless confident_hash.empty?

            if !change_hash.empty?
                change_reaction(change_hash)
            elsif !maybe_hash.empty?
                did_you_say_reaction(maybe_hash)
            elsif confident_hash.empty?
                if escape(utterance)
                    return @selections
                else
                    extracted_nothing_reaction
                end
            end
        end
        final_selection_reaction
        return @selections
    end

# TODO: need to get rid of phrasing overlaps
    def extract(utterance, variables)
        extractions= {}
        variables.each do |variable|
            line = utterance.line
            extraction = variable.extract(utterance)
            top_extraction = variable.top_extraction(extraction)
            extractions[variable] = top_extraction
            #if top_extractions.size == 0
            #    confidence = 0
            #else
            #    confidence = calc_confidence(utterance, top_extractions)
            #end
            #top_extractions.confidence = confidence
            #puts "(DEBUG) confidence: " + confidence.to_s if DEBUG
        end
        return extractions
    end

# sets @selections and grounds them,
# will be called by change_reaction and did_you_say_reaction
    def selection_reaction(selections)
        # set the selections
        selections.each do |variable, selection|
            @selections[variable] = selection
        end
        # do individual responses
        selections.each do |variable, selection|
            responses = selection.map(&:response).compact
            # value specific responses
            responses.each{|response| puts response}
            # general variable response 
            puts variable.response unless variable.response.nil?
        end
        # do the grounding for variables with more than one value
        singular_selections = {}
        selections.each do |variable, selection|
            if selection.size > 1
                puts variable.grounding(selection, 1.5)
            else
                singular_selections[variable] = selection
            end
        end
        # do the grounding for the other variables
        if singular_selections.size == 1
            puts "#{Util.english_list(singular_selections.values.map{|selection| selection.first})} was set for the #{Util.english_list(singular_selections.keys.map(&:name))}."
        else
            puts "#{Util.english_list(singular_selections.values.map{|selection| selection.first})} were set for the #{Util.english_list(singular_selections.keys.map(&:name))}."
        end
    end

    # gets all extractions that have a single value, or gets the best extraction with multiple values
    def simpler_group(extractions_hash)
        return extractions_hash if extractions_hash.empty?
        singular_extractions_hash = extractions_hash.select{|variable, extractions| extractions.size == 1}
        if singular_extractions_hash.empty?
            pair = extractions_hash.max_by{|variable, extractions| extractions.confidence}
            return {pair[0] => pair[1]}
        else
            return singular_extractions_hash
        end
    end

    def remaining_vars_prompt
        "What is your #{Util.english_list(remaining_vars.map(&:name))}?"
    end

    def extracted_nothing_reaction
        puts "extracted nothing reaction" if DEBUG
        @reprompt = false unless @last_extracted_nothing == @run_count - 1
        @last_extracted_nothing = @run_count
        puts extracted_nothing_prompt
    end

    def extracted_nothing_prompt
        apologetic(dont_understand_prompt)
    end

    def dont_understand_prompt
        "I don't understand what you said."
    end

    def calc_confidence(utterance, extractions)
        confidence = utterance.map(&:confidence).reduce(:+) / utterance.size
        (confidence + extractions.map(&:confidence).max) / 2
    end

# TODO: change to be same format as did_you_say_reaction
    def change_reaction(extractions)
        puts "change reaction" if DEBUG
        puts apologetic(change_prompt(extractions))
    end

    # logic for this is made simpler by the simpler_group method
    def change_prompt(extractions)
        return "Were you trying to change #{extractions.keys.first.name} to #{Util.english_list(extractions.values.first)}?"
    end

    # logic for this is made simpler by the simpler_group method
    def did_you_say_prompt(extractions)
        if extractions.size == 1
            "Did you say #{Util.english_list(extractions.values.first)} for the #{extractions.keys.first.name}?"
        else
            "Did you say #{Util.english_list(extractions.values.map{|x| x.first})} for the #{Util.english_list(extractions.keys.map(&:name))}?"
        end
    end

# same format as change_reaction
    def did_you_say_reaction(extractions)
        puts "did you say reaction" if DEBUG
        puts apologetic(did_you_say_prompt(extractions))
        @utterances << get_input
        utterance = @utterances.last
        answer = Util.extract_yes_no(utterance)
        next_extractions = extract(utterance, extractions.keys)#.select{|var, extraction| extraction.confidence > @change_threshold}

        # determines what selections are they trying to correct to
        selections = nil
        if answer == 'no'
            rejection_likelihood(extractions, answer.confidence)
            #puts "YO YO YO YO YO"
            #p extractions
            #p next_extractions
            selections = next_extractions.select{|var, extraction| extraction != extractions[var]}
            #p selections
            increase_likelihood(selections)
        else
            if answer == 'yes'
                selections = extractions
                confirmation_likelihood(selections, answer.confidence)
            end
# does this comparison work?
            if extractions == next_extractions
                selections = extractions
                confirmation_likelihood(selections, next_extractions.values.map(&:confidence).min)
            end
        end

        p selections if DEBUG

        # determines what to do with these selections
        if selections == nil
            puts apologetic(dont_understand_prompt)
            # TODO: slightly increase next_extractions_hash.likelihood
        else
            confident_hash = selections.select{|var, extraction| p extraction.confidence if DEBUG; extraction.confidence >= @select_threshold}
            maybe_hash = selections.select{|var, extraction| p extraction.confidence if DEBUG; extraction.confidence >= @clarify_threshold}
            p confident_hash if DEBUG
            if confident_hash.size == selections.size
                selection_reaction(confident_hash)
            elsif confident_hash.size > 0
                did_you_say_reaction(confident_hash)
            elsif maybe_hash.size > 0
                did_you_say_reaction(maybe_hash)
            else
                puts apologetic(dont_understand_prompt)
                # TODO: slightly increase next_extractions_hash.likelihood
            end
        end
    end

# when overlapped, increase probability of both values in both variables (or could be more than 2), but not as big an increase (for n overlap, could divide by n)

# replacements: look for "change", "actually", "replace", etc. and name of variable in selections
# coder will need to be able to put in synonyms for name of variable
    def extract_change(utterance, variables)
        change_hash = {}
        variables.each do |variable|
            if utterance.include? variable.name && !(utterance | Util.change_set).empty?
                extractions = variable.extract(utterance)
# TODO: make threshold also consider confidence in variable.name and change_set
                if !extractions.empty? && extractions.confidence >= change_threshold
                    change_hash[variable] = extractions
                end
            end
        end
        return change_hash
    end

    def rejection_likelihood(extractions, confidence)
        extractions.each do |variable, extraction|
            extraction.each do |value|
                #variable.prob_mass += extraction.likelihood * confidence
                p value
                p confidence
                value.confidence -= confidence
            end
        end
    end

    def increase_likelihood(extractions)
        extractions.each do |variable, extraction|
            extraction.each do |value|
                #variable.prob_mass += extraction.likelihood * confidence
                value.confidence += value.confidence / 2
            end
        end
    end

    def confirmation_likelihood(extractions, confidence)
        extractions.each do |variable, extraction|
            extraction.each do |value|
                #variable.prob_mass += extraction.likelihood * confidence
                p value.confidence
                value.confidence += value.confidence * confidence
            end
        end
    end

    def escape(utterance)
        puts "escape" if DEBUG
        false
    end

    def final_selection_reaction
    end

    def apologetic(prompt)
        @apologies += 1
        if @apologies < 2
            prompt
        else
            #puts Util.sorry_words[@repetitions % Util.sorry_words.size].capitalize + ', ' + prompt[0].downcase + prompt[1..-1]
            Util.sorry_words[(@apologies - 2) % Util.sorry_words.size].capitalize + ', ' + prompt
        end
    end
end

# class SlotGroup ?
# is there a need for a tree class or will that just fall out of how you write it?
