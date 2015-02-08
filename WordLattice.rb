require './Util'
require 'set'

# probabilities leading out of a node must sum to <= 1

# no .number assumes uniform probability

# no edge listed, assume it comes right after previous word:
# (1,2) wettbwerbs.25 bedingten.4

# no edge listed for first word, assume it feeds into first node

# lowest number node is the start node

# example sentence:
# (0,1) einen (1,2) wettbwerbs.25 (1,2) wettbwerb.25 (2,3) bedingten.4 preissturz.7

# (0,1) einen \
# (1,2) wettbwerbs.25 \
# (1,2) wettbwerb.25 \
# (2,3) bedingten.4 preissturz.7

# TODO make WordLattice extend/implement UserUtterance?

class WordLattice

    def nodes
        return @nodes
    end

    def initialize(input)
        @nodes = {}
        @start_node = nil
        self.parse(input)
    end

    # convert String form to graph form
    def parse(input)
        while(!input.empty?)
            input = parse_edge(input)
            if input.nil?
                raise 'error parsing'
                return nil
            end
        end
        self.assign_uniform_probs
        @start_node = self.get_start_node
    end

    def assign_uniform_probs
        @nodes.values.each do |node|
            num_edges = node.edges_out.count{|edge| edge.phrase.first.probability.nil?}
            node.edges_out.each do |edge|
                edge.phrase.first.probability = 1.0/num_edges if edge.phrase.first.probability.nil?
            end
        end
    end

    # right now gets lowest numbered node
    # TODO: handle leading node shenanigans
    # TODO: do this smarter
    def get_start_node
        return @nodes.reduce{|sum, pair| pair[0] < sum[0] ? pair : sum}[1] 
    end

    def parse_edge(input)
        edge_regex = /^\s*\((\d+), ?(\d+)\)/
        word_regex = /^\s*([a-zA-Z'-]+)(\.\d+)?[,!?;.]?/
        match = edge_regex.match(input)
        if match.nil?
            match = word_regex.match(input)
            if match.nil?
                return nil # parsing failed
            else
                input.slice!(0...match.end(0))
                # should only hit here once, at very start of the input
                # TODO make special starting edge
            end
        else
            from_index, to_index = match.captures
            edge = Edge.new(from_index, to_index)

            @nodes[from_index] = Node.new() if @nodes[from_index].nil?
            @nodes[to_index] = Node.new() if @nodes[to_index].nil?
            @nodes[from_index].edges_out << edge

            input.slice!(0...match.end(0))
            match = word_regex.match(input)
            return nil if match.nil? # parsing failed
            word, prob = match.captures
            edge.phrase << Word.new(word, prob.nil? ? nil : prob.to_f)

            while true do
                input.slice!(0...match.end(0))
                match = word_regex.match(input)
                break if match.nil?
                word, prob = match.captures
                edge.phrase << Word.new(word, prob.nil? ? 1.0 : prob.to_f)
            end
        end
        return input
    end

    # convert to String form
    def to_s
        return @nodes.values.map{|node| node.to_s}.join
        #return @nodes.values.reduce(''){|sum, node| sum + node.to_s}
    end

    def multiline_to_s
        return @nodes.values.map{|node| node.multiline_to_s}.join
        #return @nodes.values.reduce(''){|sum, node| sum + node.multiline_to_s}
    end

# TODO after the word lattice searching is done, make method for choosing between synonyms that look the same, using likelihood

    def find_synonyms(synonyms)
        return self.find_helper(@start_node, synonyms)
    end

    def find_helper(node, synonyms)
        matches = PrioritySet.new()
        #puts "---NODE---"
        node.edges_out.each do |edge|
            #print "edge ", edge, "\n"
            new_syns = synonyms.clone
            synonyms.each do |syn|
                ms = WordLattice.match_phrase(syn, edge.phrase)
                new_syns |= ms
                #new_syns |= WordLattice.match_phrase(syn, edge.phrase)
                #puts new_syns
            end
            matches |= find_helper(@nodes[edge.to_id], new_syns)
        end
#TODO stop repeating work
        synonyms.each do |syn|
            if syn.finished_matching? && !node.edges_out.find{|edge| !WordLattice.match_phrase(syn, edge.phrase).empty?}
                matches << syn
            end
        end
        return matches
    end

    # gotta handle blank as well

    # return synonyms that match all the words in the phrase or synonyms that are finished and match as many words as possible in the phrase
    def self.match_phrase(synonym, phrase)
        return PrioritySet.new([synonym]) if phrase.empty?
        matches = PrioritySet.new()
        new_syns = synonym.match_word(phrase.first)
        new_syns.each do |new_syn|
            new_matches = self.match_phrase(new_syn, phrase.drop(1))
            if new_matches.empty?
                matches << new_syn if new_syn.finished_matching?
            else
                matches |= new_matches
            end
        end
        return matches
    end

    protected :find_helper, :parse_edge, :assign_uniform_probs
end

class Node
    attr_accessor :edges_out

    def initialize()
        self.edges_out = []
    end

    def to_s
        #return edges_out.reduce(''){|sum, edge| sum + edge.to_s + ' '}[0..-2]
        return edges_out.join(' ')
    end

    def multiline_to_s
        #return edges_out.reduce(''){|sum, edge| sum + edge.to_s + " \\\n"}
        return edges_out.join(" \\\n")
    end
end

class Edge
    attr_accessor :phrase, :from_id, :to_id, :is_first

    def initialize(from_id, to_id, phrase = Phrase.new([]), is_first = false)
        self.phrase = phrase; self.from_id = from_id; self.to_id = to_id; self.is_first = is_first
    end

    def to_s
        # don't include edge if it's the only possible start
        if self.is_first && words.size == 1
            string = ''
        else
            string = "(#{self.from_id},#{self.to_id}) "
        end
        return string + self.phrase.formatted
    end
end

class Word < String

    attr_accessor :probability

    def initialize(word, probability = 1.0)
        self.probability = probability
        super(word)
    end

    def formatted
        # don't include probability of it's certain to be it
        if self.probability == 1.0
            return self.to_s
        else
            return "#{self.to_s}#{self.probability.to_s[1..-1]}"
        end
    end

    alias :to_s :to_str
end

# Phrase is just a list of Word
class Phrase < Array

    #attr_accessor :words

    def initialize(words = [])
    #    self.words = words
        words = words.split if words.is_a? String
        words = Util.listify(words)
        words.map!{|word| word.is_a?(Word) ? word : Word.new(word)}
        super(words)
    end

    def ==(other)
        return self.size == other.size && !self.zip(other).find{|x, y| x != y}
    end

    def subsumed_by?(other)
        return self == other && !self.zip(other).find{|my_word,their_word| my_word.probability > their_word.probability}
    end

    def subsumes?(other)
        return other.subsumed_by?(self)
    end

    def self.listify(arg)
        return [arg] if arg.is_a? Phrase
        return Util.listify(arg).map{|x| x.is_a?(Phrase) ? x : Phrase.new(x)}
    end

    def formatted
        return self.map{|word| word.formatted}.join(' ')
    end

    def to_str
        return self.join(' ')
    end

    alias :to_s :to_str
    alias :< :subsumed_by?
    alias :> :subsumes?
end
