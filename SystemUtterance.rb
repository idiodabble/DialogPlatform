class SystemUtterance

    attr_accessor :variants

    def initialize(variants, stay_on_last_variant = true, is_apologetic = true, is_random = false, is_pseudorandom = false)
        self.variants = Util.arrayify(variants)
        @calls = 0
        @stay_on_last_variant = stay_on_last_variant
        @is_apologetic = is_apologetic
        @is_random = is_random
        @is_pseudorandom = is_pseudorandom
        if @is_random and @is_pseudorandom
            raise "Ordering variants cannot be both random and pseudorandom"
        end
        @variants_left = Array.new(self.variants)
    end

    def get_variant
        if @is_random
            variant = choose_random_variant
        elsif @is_pseudorandom
            variant = choose_pseudorandom_variant
        else
            variant = choose_lienar_variant
        end

# TODO: make apologetic(...) platform specific?

        if @is_apologetic
            variant = Util.apologetic(variant)
        end

        @calls += 1
        return variant
    end

    def choose_random_variant
        unless @variants_left.nil?
            variant = @variants_left.sample
            if @stay_on_last_variant and variant == self.variants.last
                @variants_left = nil
            end
            return variant
        else
            return self.variants.last
        end
    end

    def choose_pseudorandom_variant
        variant = @variants_left.sample
        @variants_left = @variants_left.select{|x| x != variant}
        if !@stay_on_last_variant and @variants_left.empty?
            @variants_left = Array.new(self.variants)
        end
        return variant
    end

    def choose_linear_variant
        if @stay_on_last_variant and @calls >= self.variants.size
            return self.variants.last
        else
            return self.variants[@calls % self.variants.size]
        end
    end

    def print
        print self.get_variant
    end

end
