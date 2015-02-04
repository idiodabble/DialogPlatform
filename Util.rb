class Util
    def self.listify(arg)
        return [] if arg.nil?
        return arg if arg.is_a?(Array)
        return [arg]
    end
end
