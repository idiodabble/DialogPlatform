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
