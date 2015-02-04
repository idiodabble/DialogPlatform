require './Slot'

str = '(0,1) einen zurich (1,2) wettbwerbs (1,2) wettbwerb (2,3) bedingten.4 preissturz.7'
lattice = WordLattice.new(str)
#lattice.nodes.each{|node_pair| puts node_pair[0], node_pair[1].to_s}
#lattice.nodes.each{|node_pair| puts node_pair[0], node_pair[1].multiline_to_s}
lattice.nodes.each{|node_pair|
    puts node_pair[0]
    node_pair[1].edges_out.each{|edge|
        puts edge
    }
}
#puts lattice.multiline_to_s
#puts lattice

# [a,b,c] > a,b,c are each phrases in a list of phrases
# 'a b' > [a, b] is a phrase
syn = Synonym.new('bedingten', [Phrase.new(['einen', 'zurich', 'wettbwerbs']), Phrase.new('I am Legion')])
syn1 = Synonym.new([], 'bedingten preissturz')
syn2 = Synonym.new('bedingten preissturz', ['wettbwerbs', 'wettbwerb'])
sfsyn = Synonym.new(['SF', 'San Francisco', 'San Fran'], [], 'City')

#puts '---phrases:'
#syn.phrases.each{|x| print x, "\n"}
#puts '---prefixes:'
#syn.prefixes.each{|x| print x, "\n"}

puts "hmmmm" if "bedingten" == Word.new("bedingten")

p syn1.match_word(Word.new("bedingten"))
p syn1.match_word("bedingten")

#matches = lattice.find_synonyms([syn])
#matches.each{|match| print "match:\n", match, "\n"}
