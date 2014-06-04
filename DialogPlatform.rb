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

# Steff TODO list:

# 1. Implement try_again for did_you_say_reaction, then port everything over to change_reaction
# 2. fix scoring, do them more probablisticly - especially the rejection/confirmation/increase likelihood methods
# 3. test MultiSlot with variables with max_selections higher than 1
# 4. maybe replace @name_thresholds with name_threshold() methods
# 5. maybe rename extractions+selections again? Maybe: extractions > extraction, extractions_hash > extractions

# Bonus TODO list for if we have time:

# 1. write a Platform class, higher than Slot or MultiSlot, that will take advantage of methods like preconditions and next_slot
# 2. be able to look up things and give the user options, i.e. "There are no flights at this time" or "We have flights available for $500, $400 and $300"

DEBUG = false

class Value < String
    attr_accessor :likelihood, :phrasings, :response, :next_slot, :prefixes, :suffixes
    
# Params:
# +name+:: a string such as 'San Diego'
# +likelihood+:: likelihood of this value being selected relative to other values; does not need to be a probability
# +phrasings+:: array of regular expressions representing phrases that would indicate that the user is selecting this value
# +response+:: response given to user if the user selects this value
# +next_slot+:: next Slot to go to if the user selects this value
    def initialize(name, likelihood, prefixes = [], suffixes = [], response = nil, next_slot = nil)
        @likelihood = likelihood; @prefixes = prefixes; @suffixes = suffixes; @response = response; @next_slot = next_slot
        super(name)
    end
end

#
class Variable
    attr_accessor :name, :values, :prob_mass, :max_selection, :selection, :prefixes, :suffixes

    # Params:
    # +name+:: name of the variable, such as 'departure city'
    # +values+:: can be an array of Values, see above
    #         or it can be an array of strings such as ['San Diego', 'San Fransisco', 'Sacramento']
    #         using defaults to fill in the other fields for Values
    # +prob_mass+:: because likelihoods don't have to be probabilities, the total probability mass may not be 1
    # +max_selection+:: the number of values a user can set at one time
    #    example: when set to 2, 'San Diego' or 'San Diego and San Francisco' are valid responses,
    #    but 'San Diego, San Francisco, and Los Angeles' is not
    def initialize(name, values, max_selection = 1, prefixes = [], suffixes = [])
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
        @prob_mass = @values.map(&:likelihood).reduce(:+)
        @max_selection = max_selection
        @prefixes = prefixes
        @suffixes = suffixes
    end

    def response
        nil
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

    def did_you_say_prompt(extractions)
        "I didn't hear you, did you say #{Util.english_list(extractions.map(&:value))}?"
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
        extractions = Extractions.new

        @values.each do |value|
            confidence = calc_confidence(utterance, value)
            puts "(DEBUG) value: #{value} confidence: #{confidence}" if DEBUG
            extractions << Extraction.new(value, confidence * confidence.abs, 0)
        end
        #scores_to_prob(extractions)
        #puts "(DEBUG) extractions: " + extractions.to_s if DEBUG
        return extractions
    end

    # extractions = @values.map { |value|
    #     phrasings = value.phrasings.nil? ? phrasings(value) : value.phrasings
    #     phrasing = phrasings.find{|phrasing| line[phrasing] != nil}
    #     unless phrasing.nil?
    #         confidence = calc_confidence(utterance, value, phrasing)
    #         # TODO: could get position this when we do line[phrasing]
    #         Extraction.new(value, confidence, line.index(phrasing))
    #     end
    # }.compact
    # orders the extractions by probability, then by most recently said in utterance
    # also, what to do if 'san francisco' said once but 'san diego' said twice?

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
        line = utterance.line
        phrasings = get_possible_phrasings(line, value)
        # p "phrasings", phrasings
        max_score = 0
        line_len = line.length
        phrasings.each do |phrase|
            score = 0
            phrase_len = phrase.length
            if line_len > phrase_len
                if line_len > phrase_len + 10
                    max_length = phrase_len + 10
                else
                    max_length = line_len
                end
                (phrase_len..max_length).each do |size|
                    (0..(line_len - size - 1)).each do |start_index|
                        sub_str = line[start_index, start_index + size]
                        score = edit_distance(sub_str, phrase)
                        max_score = [max_score, score].max
                    end
                end
            else
                max_score = edit_distance(line, phrase)
            end
        end
        max_score
    end

    def get_possible_phrasings(line, value)
        #p "line", line, "value", value
        valid_phrasings = [value]
        prefixes = @prefixes.concat value.prefixes
        suffixes = @suffixes.concat value.suffixes
        prefixes.each do |pre|
            if line.include? pre
                valid_phrasings << (pre + ' ' + value)
            end
        end
        suffixes.each do |suf|
            if line.include? suf
                valid_phrasings << (value + ' ' + suf)
            end
        end
        valid_phrasings
    end

    def edit_distance(line, phrasing)
        l = line.downcase
        p = phrasing.downcase
        l_len = line.length
        p_len = phrasing.length
        return p_len if l_len == 0
        return l_len if p_len == 0
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

    def scores_to_prob(extractions)
        sum = 0
        extractions.each do |extraction|
            sum = sum + extraction.confidence
        end
        return if sum == 0
        extractions.each do |extraction|
            extraction.confidence /= sum
        end
    end

    def top_extractions(extractions)
        Extractions.new(extractions.sort{|a, b|
            first_order = b[:confidence] <=> a[:confidence]
            first_order == 0 ? b[:position] <=> a[:position] : first_order
        }.first @max_selection)
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
end

# An extraction, singular, has a single value
# Multiple extractions, plural, can be extracted at a time if max_selections > 1
Extraction = Struct.new(:value, :confidence, :position)

class Extractions < Array
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

    def get_input
        #p @variable.values.map{|value| [value.likelihood, value]} if DEBUG
        line = gets.chomp.downcase
        
        utterance = Utterance.new(line.scan(/([\w'-]+)[\.\?!,]?\s?(\([\+-]?[\d.]+\))?/).map{|word, confidence| confidence.nil? ? Word.new(word, 1) : Word.new(word, confidence[1...-1].to_f)})
        if utterance.find{|word| word.confidence <= 0 || word.confidence > 1}
            puts "Malformed input: Confidence should be in the range (0,1]. Please respond again."
            return get_input
        end
        return utterance
    end

    def run_cycle
        @utterances << get_input
        while(true)
            extract_selection(@utterances.last)
            if @confidence >= @extract_threshold
                break
            elsif @confidence >= @clarify_threshold
#TODO: need to increase likelihood of all extractions, not just top
                break if did_you_say_reaction
            else
                # returns nil so coder deccides whether to use run_clarification or do something else,
                # because maybe the user is trying to jump
                if escape(@utterances.last, @selections)
                    return nil
                else
                    clarification_reaction
                end
            end
            @repetitions += 1
        end
        selection_reaction
        return @selections
    end

    # style question: keep parameters or keep class fields?
    def did_you_say_reaction
        puts apologetic(@variable.did_you_say_prompt(@selections))
        @utterances << get_input
        line = @utterances.last.line
        if Util.no_set.include? line
            rejection_likelihood(@selections) if @selections.size == 1
            puts "Oh, what did you mean?"
            @utterances << get_input
        elsif Util.no_set.find{|no_word| line[no_word] != nil} != nil
            rejection_likelihood(@selections) if @selections.size == 1
        elsif Util.yes_set.find{|no_word| line[no_word] != nil} != nil
            return true
        else
            repetition_likelihood(@extractions)
        end
        return false
    end

    # again, do something less dumb
    def rejection_likelihood(extractions)
        repetition_likelihood(@variable.values - extractions)
    end

    # style question: what to name the parameter?
    def repetition_likelihood(extractions)
        extractions.each{|extraction|
            @variable.prob_mass += extraction.value.likelihood
            # TODO: make this not dumb
            extraction.value.likelihood += extraction.confidence
        }
    end

    # this is how the coder can escape the Slot, in case the user is trying to exit or jump elsewhere
    # TODO: create an example of escape in either Reservation.rb or a higher level class
    def escape(utterance, extractions)
        false
    end

    def clarification_prompt
        puts apologetic("I'm not sure what you said, could you repeat your response?")
    end

    def clarification_reaction
        clarification_prompt
        repetition_likelihood(@extractions)
        @utterances << get_input
    end

    def selection_reaction
        selected_vals = @selections.map(&:value)
        responses = selected_vals.map(&:response).compact
        # value specific responses
        responses.each{|response| puts response}
        # general variable response 
        puts @variable.response unless @variable.response.nil?
        # more succinct in following runs
        if @run_count > 1
            puts @variable.grounding(selected_vals, 2)
        else
            puts @variable.grounding(selected_vals, 1)
        end
    end

    # sets @extractions, @selections and @confidence
    # returns 0 if it couldn't find anything at all,
    # otherwise returns confidence probability
    def extract_selection(utterance)
        @extractions = @variable.extract(utterance)
        p @extractions if DEBUG
        @selections = @variable.top_extractions(@extractions)
        if @extractions.size == 0
            @confidence = 0
        else
            @confidence = calc_confidence(@selections)
        end
        #puts "(DEBUG) confidence: " + @confidence.to_s if DEBUG
    end

    def calc_confidence(extractions)
        extractions.map(&:confidence).min
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
        puts @prompts[@run_count % @prompts.size]
    end

    def get_input
        line = gets.chomp.downcase
        utterance = Utterance.new(line.scan(/([\w'-]+)[\.\?!,]?\s?(\([\+-]?[\d.]+\))?/).map{|word, confidence| confidence.nil? ? Word.new(word, 1) : Word.new(word, confidence[1...-1].to_f)})
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

            extractions_hash = extract(utterance, remaining_vars)
            confident_hash = extractions_hash.select{|var, extractions| extractions.confidence >= @select_threshold}
            change_hash = simpler_group(extract_change(utterance, @selections.keys))
            maybe_hash = extractions_hash.select{|var, extractions| extractions.confidence < @select_threshold && extractions.confidence >= @clarify_threshold}

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
        extractions_hash = {}
        variables.each do |variable|
            line = utterance.line
            p variable.name if DEBUG
            extractions = variable.extract(utterance)
            top_extractions = variable.top_extractions(extractions)
            extractions_hash[variable] = top_extractions
            #if top_extractions.size == 0
            #    confidence = 0
            #else
            #    confidence = calc_confidence(utterance, top_extractions)
            #end
            #top_extractions.confidence = confidence
            #puts "(DEBUG) confidence: " + confidence.to_s if DEBUG
        end
        return extractions_hash
    end

# sets @selections and grounds them,
# will be called by change_reaction and did_you_say_reaction
    def selection_reaction(selections_hash)
        # set the selections
        selections_hash.each do |variable, selections|
            @selections[variable] = selections
        end
        # do individual responses
        selections_hash.each do |variable, selections|
            responses = selections.map(&:value).map(&:response).compact
            # value specific responses
            responses.each{|response| puts response}
            # general variable response 
            puts variable.response unless variable.response.nil?
        end
        # do the grounding for variables with more than one value
        singular_selections_hash = {}
        selections_hash.each do |variable, selections|
            if selections.size > 1
                puts variable.grounding(selections.map(&:value), 1.5)
            else
                singular_selections_hash[variable] = selections
            end
        end
        # do the grounding for the other variables
        if singular_selections_hash.size == 1
            puts "#{Util.english_list(singular_selections_hash.values.map{|selections| selections.first.value})} was set for the #{Util.english_list(singular_selections_hash.keys.map(&:name))}."
        else
            puts "#{Util.english_list(singular_selections_hash.values.map{|selections| selections.first.value})} were set for the #{Util.english_list(singular_selections_hash.keys.map(&:name))}."
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
    def change_reaction(extractions_hash)
        puts apologetic(change_prompt(extractions_hash))
    end

    # logic for this is made simpler by the simpler_group method
    def change_prompt(extractions_hash)
        return "Were you trying to change #{extractions_hash.keys.first.name} to #{Util.english_list(extractions_hash.values.first.map(&:value))}?"
    end

    # logic for this is made simpler by the simpler_group method
    def did_you_say_prompt(extractions_hash)
        if extractions_hash.size == 1
            return "Did you say #{Util.english_list(extractions_hash.values.first.map(&:value))} for the #{extractions_hash.keys.first.name}?"
        else
            return "Did you say #{Util.english_list(extractions_hash.values.map{|x| x.first.map(&:value)})} for the #{Util.english_list(extractions_hash.keys.map(&:name))}?"
        end
    end

# same format as change_reaction
    def did_you_say_reaction(extractions_hash)
        puts apologetic(did_you_say_prompt(extractions_hash))
        @utterances << get_input
        utterance = @utterances.last
        answer = extract_yes_no(utterance)
        next_extractions_hash = extract(utterance, extractions_hash.keys).select{|var, extractions| extractions.confidence > @change_threshold}

        # determines what selections are they trying to correct to
        selections_hash = nil
        if answer.value == :no
p "yo yo"
            rejection_likelihood(extractions_hash, answer.confidence)
            increase_likelihood(new_extractions_hash)
            selections_hash = next_extractions_hash.select{|var, extractions| extractions != extractions_hash[var]}
p selections_hash
        else
            if answer.value == :yes
                confirmation_likelihood(extractions_hash, answer.confidence)
                selections_hash = extractions_hash
            end
# does this comparison work?
            if extractions_hash == next_extractions_hash
                confirmation_likelihood(extraction_hash, next_extractions_hash.values.map(&:confidence).min)
                selections_hash = extractions_hash
            end
        end

        # determines what to do with these selections
        if selections_hash == nil
            puts apologetic(dont_understand_prompt)
            # TODO: slightly increase next_extractions_hash.likelihood
        else
            confident_hash = selections_hash.select{|var, extractions| extractions.confidence >= @select_threshold}
            if confident_hash.size == selections_hash.size
                selection_reaction(confident_hash)
            else
                # TODO: try again
                puts 'this is temporary'
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

    def extract_yes_no(utterance)
        if utterance.size == 1
            word = utterance.first
            if Util.no_set.include? word
                return Extraction.new(:no, word.confidence) 
            elsif Util.yes_set.include? word
                return Extraction.new(:yes, word.confidence)
            end
        end
        no = utterance.find{|word| Util.no_set.include? word}
        yes = utterance.find{|word| Util.yes_set.include? word}
        if no && yes.nil?
            return Extraction.new(:no, no.confidence / utterance.size)
        elsif no.nil? && yes
            return Extraction.new(:yes, yes.confidence / utterance.size)
        end
        return Extraction.new
    end

    # TODO: need to figure out which likelihoods need to change. Extractions? Extraction? Value?

    def rejection_likelihood(extractions_hash, confidence)
        extractions_hash.each do |variable, extractions|
            extractions.each do |extraction|
                #variable.prob_mass += extraction.likelihood * confidence
                extraction.likelihood -= confidence
            end
        end
    end

    def increase_likelihood(extractions_hash)
        extractions_hash.each do |variable, extractions|
            extractions.each do |extraction|
                #variable.prob_mass += extraction.likelihood * confidence
                extraction.likelihood += extraction.likelihood / 2
            end
        end
    end

    def confirmation_likelihood(extractions_hash, confidence)
        extractions_hash.each do |variable, extractions|
            extractions.each do |extraction|
                #variable.prob_mass += extraction.likelihood * confidence
                extraction.likelihood += extraction.likelihood * confidence
            end
        end
    end

    def escape(utterance)
        false
    end

# TODO
    def final_selection_reaction
    end

    def apologetic(prompt)
        if @run_cycles < 2
            puts prompt
        else
            #puts Util.sorry_words[@repetitions % Util.sorry_words.size].capitalize + ', ' + prompt[0].downcase + prompt[1..-1]
            puts Util.sorry_words[(@run_cycles - 2) % Util.sorry_words.size].capitalize + ', ' + prompt
        end
    end
end

# class SlotGroup ?
# is there a need for a tree class or will that just fall out of how you write it?
