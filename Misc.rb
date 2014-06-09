require './Util'

# An Utterance is an array of Words.
# Call line to get a string version of the utterance.
class Utterance < Array
    def line
        self.join(' ')
    end

    def select_slice(start, length)
        sliced = self.slice(start, length)
        return sliced.join(' '), sliced
    end
end

# An Extraction is an Array of Value
class Extraction < Array
    def confidence
        self.map(&:confidence).min
    end
end

class Value < String
    attr_accessor :prior, :confidence, :phrasings, :response, :next_slot, :prefixes, :suffixes, :synonyms, :word_indexes
    
    # Params:
    # +name+:: a string such as 'San Francisco'
    # +prior+:: prior probability of this value being selected, e.g. "San Francisco" having 0.3 and "San Diego" having 0.2 because SFO is more popular; must be a number in (0,1)
    # +confidence+:: confidence that this value is being selected by the user; must be a number but does not have to be a probability
    # +prefixes+:: words that we might expect to see before the value, e.g. "from" or "to"
    # +suffixes+:: words that we might expect to see after the value, e.g. "airport"
    # +synonyms+:: words that we might expect in place of the value, e.g. "San Fran"
    # +response+:: response given to user if the user selects this value
    # +next_slot+:: next Slot to go to if the user selects this value
    def initialize(name, prior, confidence = prior, prefixes = [], suffixes = [], synonyms = [], response = nil, next_slot = nil, word_indexes = nil)
        @prior = prior; @confidence = confidence; @prefixes = prefixes; @suffixes = suffixes; @synonyms = synonyms; @response = response; @next_slot = next_slot
        super(name)
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
            confidence, words = calc_confidence(utterance, value)
            #value.confidence = confidence * confidence.abs
            if confidence > 0
                value.confidence = (value.confidence + 2 * confidence) / 3
                value.word_indexes = words
            end
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
        max_score = 0
        max_words_used = []
        phrasings.each do |phrase|
            score = 0
            phrase_len = phrase.length
            (1..utterance.length).each do |num_words|
                (0..(utterance.length - num_words)).each do |start_index|
                    sub_str, words = utterance.select_slice(start_index, start_index + num_words)
                    score = edit_distance(sub_str, phrase, value)
                    # p "score", score, "phrase", phrase, "value", value
                    if score > max_score then
                        max_score = score
                        max_words_used = words
                    end
                end
            end
        end
        return max_score, max_words_used
    end

    # Checks input for possible phrasings for the input
    def get_possible_phrasings(utterance, value)
        #p "line", line, "value", value
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

    def edit_distance(sub_str, phrasing, value)
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
        len = [l_len, value.length].max
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
