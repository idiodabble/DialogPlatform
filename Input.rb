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
    # You can just call Utterance.new(gets.chomp)
    def initialize(line)
        super(line.downcase.scan(/([\w'-]+)[\.\?!,]?\s?(\([\+-]?[\d.]+\))?/).map{|word, confidence| confidence.nil? ? Word.new(word, 1.0) : Word.new(word, confidence[1...-1].to_f)})
    end

    def line
        self.join(' ')
    end

    def select_slice(start, length)
        sliced = self.slice(start, length)
        indexes = Array.new
        (start..(start + length - 1)).each do |index|
            indexes << index
        end
        #p "line", self.line, "length", length, "indexes", indexes
        return sliced.join(' '), indexes
    end
end