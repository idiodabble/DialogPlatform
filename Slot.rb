require 'set'
require './Util'
require './WordLattice'

class Slot

    def initialize(choices, sufficient_num_choices = choices.size, sufficient_groups = [])
        self.choices = Util.listify(choices)
        @num_choices_made = 0
        @sufficient_num_choices = sufficient_num_choices
        @choices_made = set()
        @sufficient_groups = sufficient_groups
    end

    def finished?
        if @num_choices_made >= @sufficient_num_choices
            return true
        elsif @sufficient_groups.find{|group| group.subset? @choices_made}
            return true
        else
            return false
        end
    end

    def run(platform)
        prompt
        get_input
        respond
    end

    # has default form of prompt for choices it has
    # can handle bubbling of responses here

end

class Choice

    # response: given when an option is chosen, will replace default Slot response
    attr_accessor :name, :response, :confidence, :options, :prefixes, :suffixes

    # should be given a SystemUtterance
    attr_accessor :choice_made_response, :partial_choice_response, :did_you_say_response

    def initialize(options, sufficient_num_options = 1, sufficient_groups = [])
        self.options = Util.listify(options)
        @num_options_chosen = 0
        @sufficient_num_options = sufficient_num_options
        @options_chosen = set()
        @sufficient_groups = sufficient_groups
    end

    def finished?
        if @num_options_chosen >= @sufficient_num_options
            return true
        elsif @sufficient_groups.find{|group| group.subset? @options_chosen}
            return true
        else
            return false
        end
    end

    # need method for extracting options from input, including fill-in-the-blank
    # need method for changing option likelihoods / choosing them

# how about "would you like to undo your choice?"

end

# when analyzing an input, return a list of options and their confidences... which is distinct from this-is-what-will-actually-be-selected if I select...

# "Did you say blah?"
# yes -> NOW change probability
# no -> ???

# no... we should change probability right away, but it should be done in a different method, so multislot can prevent it if need be


# should have the bubble up system for every kind of response

class Option
    # each synonym should be a Phrase
    attr_accessor :name, :synonyms, :prior, :confidence, :prefixes, :suffixes

    # each of these should be given a SystemUtterance
    attr_accessor :chosen_response, :not_chosen_response, :did_you_say_response

    # if synonyms is empty, then this option is fill-in-the-blank
    def initialize(name, synonyms)
        synonyms = [] if synonyms.nil?
        self.synonyms = Util.listify(synonyms)
        # by default prefixes and suffixes apply to all synonyms
        self.synonyms.each{|syn| syn = Synonym.new(syn, prefixes, suffxies) if !syn.is_a? Synonym}
        self.name = name
    end
end

# An Option is in essence a specific idea, and this idea may be representable in different ways, each of those ways synonymous. Hence, we use the Synonym class to represent how an Option might be worded. An Option may have multiple Synonyms, and each Synonym can map to multiple real-language phrasings.
# Prefixes and Suffixes are used to increase the confidence...
class Synonym

    attr_accessor :phrases, :prefixes, :suffixes, :phrase_matched, :prefix_matched, :suffix_matched

# how to handle nil arg?
    def initialize(phrases, prefixes = [], suffixes = [], stage = :can_prefix)
        self.phrases = Phrase.listify(phrases)
        self.prefixes = Phrase.listify(prefixes)
        self.suffixes = Phrase.listify(suffixes)
        self.phrase_matched = []; self.prefix_matched = []; self.suffix_matched = []
        @stage = stage
    end

    def clone(stage = @stage)
        syn = Synonym.new(self.phrases.clone, self.prefixes.clone, self.suffixes.clone, stage)
        syn.prefix_matched = self.prefix_matched; syn.phrase_matched = self.phrase_matched; syn.suffix_matched = self.suffix_matched
        return syn
    end

    def finished_matching?
        return @stage == :finished || @stage == :on_end
    end

    # returns list of synonyms, if word doesn't match, return empty list
    # otherwise return new Synonym with word added in
    def match_word(word)
        puts 'matching word!!!!'
        puts @stage
        syns = []
        case @stage
        # can_prefix means you can start/continue a prefix or just start the phrase
        # can_suffix means you've finished matching and can continue the phrase or just start a suffix
        when :can_prefix, :on_prefix
            new_syn = match_prefix(word)
            syns << new_syn if !new_syn.nil?
        when :can_prefix, :on_phrase, :can_suffix
            new_syn = match_phrase(word)
            syns << new_syn if !new_syn.nil?
        when :can_suffix, :on_suffix, :finished
            new_syn = match_suffix(word)
            syns << new_syn if !new_syn.nil?
        end
        return syns
    end

# TODO fill-in-the-blank
# will need a max number of words, and just needs to modify match_phrase

# should probably test this out first

    def match_prefix(word)
        puts 'matching prefix!!!'
        prefixes = @prefixes.select{|prefix| prefix.first == word}
        return nil if prefixes.empty?
        prefixes = prefixes.map{|prefix| prefix.drop(1)}
        stage = prefixes.find{|prefix| prefix.empty?} ? :can_prefix : :on_prefix
        syn = self.clone(stage)
        syn.prefixes = prefixes.select{|prefix| !prefix.empty?}
        syn.prefix_matched << word
        return syn
        #return Synonym.new(@phrases, prefixes.select{|prefix| !prefix.empty?}, @suffixes, stage)
    end

# TODO: @phrase_matched/suffix_matched

    def match_phrase(word)
        phrases = @phrases.select{|phrase| phrase.first == word}
        return nil if phrases.empty?
        phrases = phrases.map{|phrase| phrase.drop(1)}
        stage = phrases.find{|phrase| phrase.empty?} ? :can_suffix : :on_phrase
        return Synonym.new(phrases.select{|prefix| !prefix.empty?}, [], @suffixes, stage)
    end

    def match_suffix(word)
        suffixes = @suffixes.select{|suffix| suffix.first == word}
        return nil if suffixes.empty?
        suffixes = suffixes.map{|suffix| suffix.drop(1)}
        stage = suffixes.find{|suffix| suffix.empty?} ? :finished : :on_suffix
        return Synonym.new(@phrases, [], suffixes.select{|prefix| !prefix.empty?}, stage)
    end
    
    protected :match_prefix, :match_phrase, :match_suffix
end
