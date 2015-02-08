require 'set'

class Util
    def self.listify(arg)
        return [] if arg.nil?
        return arg if arg.is_a?(Array)
        return arg.to_a if arg.is_a?(Set)
        return arg.to_a if arg.is_a?(PrioritySet)
        return [arg]
    end
end

# TODO subclass Set instead
class PrioritySet
    include Enumerable

    def initialize(enum = nil)
        @set = Set.new()
        @set |= enum if !enum.nil?
    end

    def clone
        return PrioritySet.new(self)
    end

    def each
        @set.each{|elem| yield elem}
    end

    def empty?
        return @set.empty?
    end

    def to_a
        return @set.to_a
    end

    def add(arg)
        if !@set.find{|elem| elem > arg}
            @set = @set.keep_if{|elem| !(elem < arg)}
            @set << arg
        end
    end

    def union(other)
        s = PrioritySet.new()        
        other.each{|elem| s.add(elem)}
        self.each{|elem| s.add(elem)}
        return s
    end

    alias :<< :add
    alias :| :union
end
