class Platform

    def initialize()
        @slots = [] # 0th element is the oldest slot
        @inputs = [] # 0th element is the oldest input
        @input = nil # most recent input, equivalent to @inputs.last
    end

    def close(slot)
        @slots.delete(slot)
    end

    def run(slot)
        finished = slot.run(self)
        while(!finished)
            # should have higher thresholds
            jump_slot = self.find_likely_slot
            unless jump_slot.nil?
            # try it, .respond(@input)? or (@choice) or () based on find_likely_slot
            # if not worked, go back to slot - but...
                # could have changed slot, now we're in it entirely
                # could DYS, but need to go back to slot!
                # not a problem: run does not loop. Whenever it fails to get info, it returns false, otherwise it goes till it gets everything
                jump_slot.respond(self)

                # markers for changing option ~ markers for changing previous options
            end
            finished = slot.run(self)
        end
        @slots << slot
    end

    # maybe first input after slot finishes is still in slot, in case of "no that's wrong!", but if it says...
    # "SFO" chosen for departure. Now when would you like to fly?
    # or do we put a pause in there? A time paused?
    # do we implement an optional is-that-correct slot?

    # should definitely implement a time limit and a no-response-in-time response
    # combined with empty prompt, this'd allow hidden pauses in which to do things

    def run_alone(slot)
        finished = slot.run(self)
        while(!finished)
            finished = slot.run(self)
        end
    end

    def find_likely_slot
        # need to handle "no go back" first, and if so return @slots.last
        # otherwise look for slots that have matching options, going backwards (recent first)
        @slots.reverse.each do |possible_slot|
            # means I need meets_threshold methods in Slot
        end
    end

    def get_input()
        @input << gets.chomp # temporary
        @inputs << @input
    end
end
