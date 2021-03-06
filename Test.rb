require './Slot'
require 'set'

str00 = '(0,1) wettbwerbs (0,1) wettbwerb (1,2) bedingten.4 preissturz.7'
str0 = '(1,2) wettbwerbs (1,2) wettbwerb (2,3) bedingten.4 preissturz.7'
str = '(0,1) einen zurich (1,2) wettbwerbs (1,2) wettbwerb (2,3) bedingten.4 preissturz.7'
lattice = WordLattice.new(str)
#lattice.nodes.each{|node_pair| puts node_pair[0], node_pair[1].to_s}
#lattice.nodes.each{|node_pair| puts node_pair[0], node_pair[1].multiline_to_s}
lattice.nodes.each{|node_pair|
#    puts node_pair[0]
    node_pair[1].edges_out.each{|edge|
#        puts edge
    }
}
#puts lattice.multiline_to_s
#puts lattice

# [a,b,c] > a,b,c are each phrases in a list of phrases
# 'a b' > [a, b] is a phrase
syn = Synonym.new('bedingten', [Phrase.new(['einen', 'zurich', 'wettbwerbs']), Phrase.new('I am Legion')])
syn1 = Synonym.new('like you', ['like', 'definitely', 'maybe'])
syn2 = Synonym.new('bedingten preissturz', ['wettbwerbs', 'wettbwerb'])
sfsyn = Synonym.new(['SF', 'San Francisco', 'San Fran'], [], 'City')

#puts '---phrases:'
#syn.phrases.each{|x| print x, "\n"}
#puts '---prefixes:'
#syn.prefixes.each{|x| print x, "\n"}

#puts 'before'
#p syn1
#puts 'after'
#p syn1.match_word(Word.new("like"))

#syna = Synonym.new([], ['wett', 'wetts'], [], :can_suffix)
#syna.phrase_matched = Phrase.new('bed preiss')
#synb = Synonym.new([], [], [], :can_suffix)
#synb.phrase_matched = Phrase.new('bed preiss')
#synb.prefix_matched = Phrase.new('wett')
#print 'heya hey ', synb.subsumed_by?(syna)
#print 'heya hey ', syna.subsumed_by?(synb)

#syns = WordLattice.match_phrase(Synonym.new('bedingten'), Phrase.new([Word.new('bedingten', 0.4), Word.new('preissturz', 0.7)]))
matches = lattice.find_synonyms(PrioritySet.new([syn2]))
matches.each{|match| p "match:\n", match}
#p matches
puts
