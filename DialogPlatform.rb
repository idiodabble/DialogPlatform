# Designed to let users easily make new dialog systems with a platform that is heavily modifiable, so it can be customized to the individual dialog system's needs.
# Author:: Daniel Steffee and Jeremy Hines

# Prioritized TODO list

# Note: I'll probably rename selections in slot to top_extractions to make it fit with Multislot terminology

# to finish up the routing logic of Multislot, I need to:
# 1. write the code for handling user trying to change previous slots
# 2. debugging
# 3. write the code for preconditions (so like, you'll only see the question about seat numbers if you're flying an airline that assigns seat numbers)

# biggest ticket items besides the routing, which Jeremy could work on if he likes:
# 1. everything to do with probability (right now I just have arbitrary hacks, like when I want something to become more likely right now I just double the scores)
# 2. edit distance

DEBUG = true

class Value < String
    attr_accessor :likelihood, :phrasings, :response, :next_slot
    
# Params:
# +name+:: a string such as 'San Diego'
# +likelihood+:: likelihood of this value being selected relative to other values; does not need to be a probability
# +phrasings+:: array of regular expressions representing phrases that would indicate that the user is selecting this value
# +response+:: response given to user if the user selects this value
# +next_slot+:: next Slot to go to if the user selects this value
    def initialize(name, likelihood, phrasings, response, next_slot)
        @likelihood = likelihood; @phrasings = phrasings; @response = response; @next_slot = next_slot
        super(name)
    end
end

#
class Variable
    attr_accessor :name, :values, :prob_mass, :max_selection, :selection

    # Params:
    # +name+:: name of the variable, such as 'departure city'
    # +values+:: can be an array of Values, see above
    #         or it can be an array of strings such as ['San Diego', 'San Fransisco', 'Sacramento']
    #         using defaults to fill in the other fields for Values
    # +prob_mass+:: because likelihoods don't have to be probabilities, the total probability mass may not be 1
    # +max_selection+:: the number of values a user can set at one time
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

    def prefixes
        @prefixes
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

    def suffixes
        @suffixes
    end

    # return array of hash of value, confidence and position
    def extract(utterance)
        line = utterance.line
        extractions = Array.new

        @values.each do |value|
            confidence = calc_confidence(line, value)
            extractions.concat << Extraction.new(value, confidence, 0)
        end
        extractions = scores_to_prob(extractions)
        puts "(DEBUG) extractions: " + extractions.to_s if DEBUG
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

    def calc_confidence(line, value)
        phrasings = get_possible_phrasings(line, value)
        max_score = 0
        line_len = line.length
        phrasings.each do |phrase|
            score = 0
            phrase_len = phrase.length
            if line_len >= phrase_len
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
        valid_phrasings = Array.new
        valid_phrasings << value
        @prefixes.each do |pre|
            if line.include? pre
                valid_phrasings << (pre + ' ' + value)
            end
        end
        @suffixes.each do |suf|
            if line.include? suf
                valid_phrasings << (value + ' ' + suf)
            end
        end
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
                        m[i-1][j-1]+1  # substitution
                    ].min
                end
            end
        end
        len = [l_len, p_len].max
        # p "edit results - " + line + " - " + phrasing + " " + (1 - m[l_len][p_len].to_f/len).to_s
        1 - (m[l_len][p_len].to_f/len)
    end

    def scores_to_prob(extractions)
        extractions
    end

    def top_extractions(extractions)
        extractions.sort{|a, b|
            first_order = b[:confidence] <=> a[:confidence]
            first_order == 0 ? b[:position] <=> a[:position] : first_order
        }.first @max_selection
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

# TODO: for input 'san diego (0.4)' does 0.4 apply to both words or just 'diego'? how to handle?
    def get_input
        p @variable.values.map{|value| [value.likelihood, value]} if DEBUG
        line = gets.chomp.downcase
        utterance = Utterance.new(line.scan(/(\S+)\s?(\([\+-]?[\d.]+\))?/).map{|word, confidence| confidence.nil? ? Word.new(word, 1) : Word.new(word, confidence[1...-1].to_f)})
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
        @selections = @variable.top_extractions(@extractions)
        if @extractions.size == 0
            @confidence = 0
        else
            @confidence = calc_confidence(@extractions)
        end
        puts "(DEBUG) confidence: " + @confidence.to_s if DEBUG
    end

    def calc_confidence(extractions)
        extractions.map(&:confidence).reduce(:+) / extractions.size
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
    def remaining_needed_vars
        @variables_needed - @selections.keys
    end

    # not intended for overwrite, just here for convenience
    def remaining_vars
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
            remaining_vars.each {|variable|
                extract_selection(@utterances.last, variable)
                selections = @selections[variable]
                extractions = @extractions[variable]
                top_extractions = @top_extractions[variable]
                if @confidences[variable] > @extract_threshold
#TODO: does the == comparison work?
                    if selections.nil? || selections == top_extraction
                        @selections[variable] = top_extractions
                        extracted_something = true
                        selection_reaction(variable, extractions)
                    end
                end
            }
# extract_replace on @selections
# if replace_reaction not called
#    did_you_say_reaction on @extractions within threshold range
# if neither of those called, remaining_vars_reaction
# (if nothing called or extracted, check if escape)
            if remaining_needed_vars.empty?
                break
            elsif extracted_something
                remaining_vars_reaction
            else
# this should be elsewhere?
# should only have at most one follow up reaction
                best_extraction = @top_extractions.values.reduce{|a,b| a.confidence > b.confidence ? a : b}
                if best_extraction.confidence >= clarify_threshold
                    break if did_you_say_reaction(best_extraction)
                else
                    if escape(@utterances.last, @extractions)
                        return nil
                    else
                        extracted_nothing_reaction
                    end
                end
            end
            @repetitions += 1
        end
        final_selection_reaction
        return @selections
    end

    def extract_selection(utterance, variable)
        line = utterance.line
# TODO: need to get rid of phrasing overlaps
        @extractions[variable] = @variable.extract(utterance)
        @top_extractions[variable] = @variable.top_extractions(@extractions)
        if extractions.size == 0
            confidence = 0
        else
            confidence= calc_confidence(utterance, @extractions)
        end
        @confidences[variable] = confidence
        puts "(DEBUG) confidence: " + @confidences[variable].to_s if DEBUG
    end

    def remaining_vars_reaction
        remaining_vars_prompt
        @utterances << get_input
    end

    def remaining_vars_prompt
        puts "What is your #{english_list(remaining_vars.map(&:name))}?"
    end

    def extracted_nothing_reaction
        extracted_nothing_prompt
        @utterances << get_input
    end

    def extracted_nothing_prompt
        puts apologetic(dont_understand_prompt)
        remaining_vars_prompt
    end

    def dont_understand_prompt
        return "I don't understand what you said."
    end

# BIGGEST TODO: use probabilities to get confidence, right now I've just got a mind boggling stupid hack
    def calc_confidence(utterance, extractions)
        confidence = utterance.map(&:confidence).reduce(:+) / utterance.size
        (confidence[variable] + extractions[variable].first.likelihood) / 2
    end

# TODO
    def replace_reaction
# check for change (change____var name: value), if accept, ask for confirmation, if yes change it, if no reduce likelihood
                    #extractions.confidence > selections.confidence
                     #   replace_response(selections, extractions, variable)
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

    def selection_reaction
        selected_vals = @selections.map(&:value)
        responses = @selected_vals.map(&:response).compact
        # value specific responses
        responses.each{|response| puts response}
        # general variable response 
        puts @variable.response unless @variable.response.nil?
        # more succinct in following runs
        if @run_count > 1
            puts @variable.grounding(@selected_vals, 2)
        else
            puts @variable.grounding(@selected_vals, 1)
        end
    end

    def replace_reaction(extractions_hash)
        puts apologetic(@variable.replace_prompt(extractions_hash))
        @utterances << get_input
        utterance = @utterances.last
        answer = extract_yes_no(utterance)
        if answer.value == :no
            rejection_likelihood(extractions_hash, answer.confidence)
            try_again = extract_replace(utterance)
            if try_again
                return replace_reaction(try_again)
            else
                return
            end
        elsif answer.value == :yes || #repeated
            confirmation_likelihood(extractions_hash, answer.confidence)
            return
        end
        puts apologetic(dont_understand_prompt)
        return
    end

    def replace_prompt(extractions_hash)
# TODO: need to be able to handle changing multiple variables
    end

    def did_you_say_prompt(extractions_hash)
# TODO: need to be able to handle changing multiple variables
    end

# same format as replace_reaction
    def did_you_say_reaction(extractions)
        puts apologetic(@variable.did_you_say_prompt(extractions_hash))
        @utterances << get_input
        utterance = @utterances.last
        answer = extract_yes_no(utterance)
        if answer.value == :no
            rejection_likelihood(extractions_hash, answer.confidence)
            try_again = extract(utterance)
            if try_again
                return did_you_say_reaction(try_again)
            else
                return
            end
        elsif answer.value == :yes || #repeated
            confirmation_likelihood(extractions_hash, answer.confidence)
            return
        end
        puts apologetic(dont_understand_prompt)
        return
    end

# when overlapped, increase probability of both values in both variables (or could be more than 2), but not as big an increase (for n overlap, could divide by n)

# replacements: look for "change", "actually", "replace", etc. and name of variable in selections
# coder will need to be able to put in synonyms for name of variable
    def extract_replace(utterance)
        false# TODO
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

    def rejection_likelihood(extractions_hash, confidence)
        inverse_hash = {}
        extractions_hash.each{|variable, extractions| inverse_hash[variable] = variable.values - extractions}
        confirmation_likelihood(inverse_hash, confidence)
    end

    def confirmation_likelihood(extractions_hash, confidence)
# TODO: if past threshold, set selections
        extractions_hash.each do |variable, extractions|
            extractions.each do |extraction|
                variable.prob_mass += extraction.value.likelihood
                extraction.value.likelihood += extraction.confidence * confidence
            end
        end
    end

    def escape(utterance, extractions)
        false
    end

    # degree is a number 0 to 3 determining how much grounding to use. 0 is none, 3 is the most verbose
    # TODO: change selections so it's the multislot hash version
    def grounding(selections, degree = 1)
        case degree
        when 1
            if selections.size <= 1
                "#{selections.first.value} was registered for the #{name}."
            else
                "#{Util.english_list(selections)} were registered for the #{name}."
            end
        when 2
            "#{Util.english_list(selections)}, #{Util.affirmation_words.sample}."
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
