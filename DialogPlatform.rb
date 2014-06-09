require 'set'
require './Misc'
require './Util'

# Designed to let users easily make new dialog systems with a platform that is heavily modifiable, so it can be customized to the individual dialog system's needs.
# Author:: Daniel Steffee and Jeremy Hines

# Jeremy TODO LIST:

# 1. Add synonyms
# 2. do multi-word prefixes work?

# Steff TODO list:

# 1. test change_reaction
# 2. test MultiSlot with variables with max_selections higher than 1
# 3. create a default variable_name prefix of some sort

# 4. change the rejection/confirmation/increase likelihood methods?
# 5. maybe replace @name_thresholds with name_threshold() methods?

# Bonus TODO list for if we have time:

# 1. Make a proper RDOC. For now, the description of the system in the writeup + comments should be enough
# 2. write a Platform class, higher than Slot or MultiSlot, that will take advantage of methods like preconditions and next_slot
# 3. be able to look up things and give the user options, i.e. "There are no flights at this time" or "We have flights available for $500, $400 and $300"

DEBUG = false

class Slot
    # prompts: an array of possible prompts
    #    a prompt is what the system tells the user at the start of the slot
    #    such as 'Where would you like to depart from?'
    # select_threshold: number between 0 and 1, user input will be accepted if confidence is above this threshold 
    # clarify_threshold: number between 0 and 1, clarification will be requested if confidence is above this threshold 
    #    and below select_threshold. If confidence is below clarify_threshold, the run method will return false
    #    and let somebody else figure out what to do
    # utterances: array containing every utterance the user has said. An utterance is an array of Words
    def initialize(variable, prompts, select_threshold = 0.6, clarify_threshold = 0.3)
        @variable = variable
        @prompts = prompts
        @select_threshold = select_threshold
        @clarify_threshold = clarify_threshold
        @utterances = []
        @run_count = 0
        @repetitions = 0
        @confidence = -1
    end

    def run
        @run_count += 1
        prompt
        run_cycle
    end

    def prompt
        if @prompts.is_a? Array
            puts @prompts[@run_count % @prompts.size]
        else
            puts @prompts
        end
    end

    def get_input
        p @variable.values.map{|value| [value.confidence, value]} if DEBUG
        line = gets.chomp.downcase
        
        utterance = Utterance.new(line.scan(/([\w'-]+)[\.\?!,]?\s?(\([\+-]?[\d.]+\))?/).map{|word, confidence| confidence.nil? ? Word.new(word, 1.0) : Word.new(word, confidence[1...-1].to_f)})
        if utterance.find{|word| word.confidence <= 0 || word.confidence > 1}
            puts "Malformed input: Confidence should be in the range (0,1]. Please respond again."
            return get_input
        end
        return utterance
    end

    def run_cycle
        @utterances << get_input
        while(true)
            @extraction = @variable.extract(@utterances.last)
            p @extraction if DEBUG
            @selection = @variable.top_extraction(@extraction)
            @confidence = @selection.confidence
            print "Selection confidence: " if DEBUG
            p @confidence if DEBUG
            if @confidence >= @select_threshold
                break
            elsif @confidence >= @clarify_threshold
                #TODO: need to increase likelihood of all extractions, not just top
                break if did_you_say_reaction(@selection)
            else
                # returns nil so coder deccides whether to use run_clarification or do something else,
                # because maybe the user is trying to jump
                if escape(@utterances.last, @selection)
                    return nil
                else
                    extracted_nothing_reaction 
                end
            end
            @repetitions += 1
        end
        selection_reaction
        return @selection
    end

    def did_you_say_reaction(extraction)
        puts "did you say reaction" if DEBUG
        puts apologetic(@variable.did_you_say_prompt(extraction))
        @utterances << get_input
        utterance = @utterances.last
        answer = Util.extract_yes_no(utterance)
        next_extraction = @variable.top_extraction(@variable.extract(utterance))

        # determines what selections are they trying to correct to
        selections = nil
        @confidence = 0
        if answer == 'no'
            rejection_likelihood(extraction, answer.confidence)
            if next_extraction != extraction
                selection = next_extraction
                increase_likelihood(selection)
            end
        else
            if answer == 'yes'
                selection = extraction
                confirmation_likelihood(selection, answer.confidence)
            end
            # does this comparison work?
            repetition = Extraction.new(extraction & next_extraction)
            if !repetition.empty?
                selection = repetition
                @confidence = selection.confidence * (repetition.size + 4) / (extraction.size + 4)
                confirmation_likelihood(selection, @confidence)
                # TODO: problem: say max_selection_size is 2 and Values are number in range [0,20]
                #                if they say "14" we should accept 14, rather than thinking they're also trying to do "1" and "4"
                #                however, if they say a bunch of different numbers and only one is in common, we don't want to think
                #                that we're doing well
            end
        end
        p selection if DEBUG
        print "confidence: " if DEBUG
        p @confidence if DEBUG

        # determines what to do with these selections
        if selection == nil
            puts apologetic(dont_understand_prompt)
            # TODO: slightly increase next_extractions_hash.likelihood
        else
            if @confidence >= @select_threshold
                @selection = selection
                return true
            elsif @confidence >= @clarify_threshold
                return did_you_say_reaction(selection)
            else
                puts apologetic(dont_understand_prompt)
                # TODO: slightly increase next_extractions_hash.likelihood
            end
        end
        return false
    end

    def rejection_likelihood(extraction, confidence)
        extraction.each do |value|
            #variable.prob_mass += extraction.likelihood * confidence
            value.confidence -= confidence
        end
    end

    def increase_likelihood(extraction)
        extraction.each do |value|
            #variable.prob_mass += extraction.likelihood * confidence
            value.confidence += value.confidence / 2
        end
    end

    def confirmation_likelihood(extraction, confidence)
        puts "confirmation likelihood" if DEBUG
        extraction.each do |value|
            #variable.prob_mass += extraction.likelihood * confidence
            value.confidence += value.confidence * confidence
            puts "#{value}: #{value.confidence}" if DEBUG
        end
    end

    # this is how the coder can escape the Slot, in case the user is trying to exit or jump elsewhere
    # TODO: create an example of escape in either Reservation.rb or a higher level class
    def escape(utterance, extractions)
        false
    end

    def extracted_nothing_prompt
        apologetic(dont_understand_prompt)
    end

    def dont_understand_prompt
        "I don't understand what you said."
    end

    def extracted_nothing_reaction
        extracted_nothing_prompt
        repetition_likelihood(@extraction)
        @utterances << get_input
    end

    def selection_reaction
        responses = @selection.map(&:response).compact
        responses.each{|response| puts response}
        # more succinct in following runs
        if @run_count > 1
            puts @variable.grounding(@selection, 2)
        else
            puts @variable.grounding(@selection, 1)
        end
    end

    def apologetic(prompt)
        if @repetitions < 1
            puts prompt
        else
            #puts Util.sorry_words[@repetitions % Util.sorry_words.size].capitalize + ', ' + prompt[0].downcase + prompt[1..-1]
            puts Util.sorry_words[(@repetitions - 1) % Util.sorry_words.size].capitalize + ', ' + prompt
        end
    end
end

# Prompts for more than one piece of information at a time
class MultiSlot
    # extractions refer to any possible selection of values we think the user might be making from their utterance
    # selections refer to extractions that we believe are true
    # both are hashes from Variable to Selection
    def initialize(variables, prompts, variables_needed = variables, select_threshold = 0.6, clarify_threshold = 0.3, change_threshold = 0.6)
        @variables = variables
        @prompts = prompts
        @select_threshold = select_threshold
        @clarify_threshold = clarify_threshold
        @change_threshold = change_threshold
        @utterances = []
        @run_count = 0
        @apologies = 0
        @selections = {}
        @variables_needed = variables_needed
    end

    # not intended for overwrite, just here for convenience
    def remaining_vars_needed
        @variables_needed - @selections.keys
    end

    # not intended for overwrite, just here for convenience
    def remaining_vars
        @variables - @selections.keys
    end

    def run
        @run_count += 1
        @run_cycles = 0
        prompt
        run_cycle
    end

    def prompt
        if @prompts.is_a? Array
            puts @prompts[@run_count % @prompts.size]
        else
            puts @prompts
        end
    end

    def get_input
        #p @variables.map{|var| var.values.map{|val| p [val, val.confidence]}} if DEBUG
        line = gets.chomp.downcase
        utterance = Utterance.new(line.scan(/([\w'-]+)[\.\?!,]?\s?(\([\+-]?[\d.]+\))?/).map{|word, confidence| confidence.nil? ? Word.new(word, 1.0) : Word.new(word, confidence[1...-1].to_f)})
        if utterance.find{|word| word.confidence <= 0 || word.confidence > 1}
            puts "Malformed input: Confidence should be in the range (0,1]. Please respond again."
            return get_input
        end
        return utterance
    end

    # is there a need for different thresholds for different variables?

    # first, extract stuff
    # if there were successful extractions, ground them
    # then, if it looks like they're trying to replace (past change_threshold), do replace reaction
    # else, if there's anything in the extract to clarify_threshold range, do did_you_say reaction
    # else, if there were no extractions and it looks like they're trying to escape (past escape_threshold?), do escape
    # else, if there were no extractions, do extracted_nothing reaction
    def run_cycle
        @reprompt = false
        while(!remaining_vars_needed.empty?)
            @run_cycles += 1
            puts remaining_vars_prompt if @reprompt
            @reprompt = true
            @utterances << get_input
            utterance = @utterances.last

            extractions = extract(utterance, remaining_vars)
            extractions.each{|var, extraction| puts var.name; extraction.each{|val| puts "value: #{val}\nconfidence: #{val.confidence}"}} if DEBUG
            confident_hash = extractions.select{|var, extractions| extractions.confidence >= @select_threshold}
            change_hash = simpler_group(extract_change(utterance, @selections.keys))
            maybe_hash = extractions.select{|var, extractions| extractions.confidence < @select_threshold && extractions.confidence >= @clarify_threshold}

            selection_reaction(confident_hash) unless confident_hash.empty?

            if !change_hash.empty?
                change_reaction(change_hash)
            elsif !maybe_hash.empty?
                did_you_say_reaction(maybe_hash)
            elsif confident_hash.empty?
                if escape(utterance)
                    return @selections
                else
                    extracted_nothing_reaction
                end
            end
        end
        final_selection_reaction
        return @selections
    end

    # TODO: need to get rid of phrasing overlaps
    def extract(utterance, variables, change_likelihood = true)
        if(variables.length == 1) then # Single-slot extract
            return extract_single_slot(utterance, variables[0], change_likelihood)
        else # Multi-slot extract
            return extract_multi_slot(utterance, variables, change_likelihood)
        end
    end

    def extract_single_slot(utterance, variable, change_likelihood = true)
        extractions = {}
        extraction = variable.extract(utterance, false, change_likelihood)
        top_extraction = variable.top_extraction(extraction)
        extractions[variable] = top_extraction
        return extractions
    end

    # Checks all the slots and attempts to assign values to each
    # If there are overlaps that can't be resolved: return true 
    # and revert to default
    def extract_multi_slot(utterance, variables, change_likelihood)
        # run all the varibles extract methods
        # make sure to know which words are used
        # if the words are overlapped, return false
        extractions = {}
        variables.each do |variable|
            extraction = variable.extract(utterance, false, change_likelihood)
            #@variables.each{|var| next unless var.name == 'time of day'; puts var.name; var.values.each{|val| puts "value: #{val}\nconfidence: #{val.confidence}"}} if DEBUG
            top_extraction = variable.top_extraction(extraction)
            p "top extraction", top_extraction[0].word_indexes if DEBUG
            extractions[variable] = top_extraction
            #puts "YO YO YO 0.5"
            #extractions.each{|var, extraction| puts var.name; extraction.each{|val| puts "value: #{val}\nconfidence: #{val.confidence}"}} if DEBUG
        end
        if(is_overlapping(extractions))
            p "There is Overlapping" if DEBUG
            new_extractions = {}
            variables.each do |variable|
                extraction = variable.extract(utterance, require_phrase, change_likelihood)
                top_extraction = variable.top_extraction(extraction)
                p "top extraction", top_extraction[0].word_indexes if DEBUG
                new_extractions[variable] = top_extraction
            end
            if(is_overlapping(new_extractions)) then
                return extractions
            else
                return new_extractions
            end
        else
            p "No Overlapping" if DEBUG
        end
        return extractions
    end

    # Checks to see if the any words are used by multiple slots
    def is_overlapping(extractions)
        top = []
        extractions.each do |variable, extraction|
            return true if !(top & extraction).empty?
            top |= extraction
        end
        return false
    end


    # sets @selections and grounds them,
    # will be called by change_reaction and did_you_say_reaction
    def selection_reaction(selections)
        # set the selections
        selections.each do |variable, selection|
            @selections[variable] = selection
        end
        # do individual responses
        selections.each do |variable, selection|
            responses = selection.map(&:response).compact
            # value specific responses
            responses.each{|response| puts response}
            # general variable response 
            puts variable.response unless variable.response.nil?
        end
        # do the grounding for variables with more than one value
        singular_selections = {}
        selections.each do |variable, selection|
            if selection.size > 1
                puts variable.grounding(selection, 1.5)
            else
                singular_selections[variable] = selection
            end
        end
        # do the grounding for the other variables
        if singular_selections.size == 1
            puts "#{Util.english_list(singular_selections.values.map{|selection| selection.first})} was set for the #{Util.english_list(singular_selections.keys.map(&:name))}."
        else
            puts "#{Util.english_list(singular_selections.values.map{|selection| selection.first})} were set for the #{Util.english_list(singular_selections.keys.map(&:name))}."
        end
    end

    # gets all extractions that have a single value, or gets the best extraction with multiple values
    def simpler_group(extractions_hash)
        return extractions_hash if extractions_hash.empty?
        singular_extractions_hash = extractions_hash.select{|variable, extractions| extractions.size == 1}
        if singular_extractions_hash.empty?
            pair = extractions_hash.max_by{|variable, extractions| extractions.confidence}
            return {pair[0] => pair[1]}
        else
            return singular_extractions_hash
        end
    end

    def remaining_vars_prompt
        "What is your #{Util.english_list(remaining_vars.map(&:name))}?"
    end

    def extracted_nothing_reaction
        puts "extracted nothing reaction" if DEBUG
        @reprompt = false unless @last_extracted_nothing == @run_count - 1
        @last_extracted_nothing = @run_count
        puts extracted_nothing_prompt
    end

    def extracted_nothing_prompt
        apologetic(dont_understand_prompt)
    end

    def dont_understand_prompt
        "I don't understand what you said."
    end

    def calc_confidence(utterance, extractions)
        confidence = utterance.map(&:confidence).reduce(:+) / utterance.size
        (confidence + extractions.map(&:confidence).max) / 2
    end

    # TODO: change to be same format as did_you_say_reaction
    def change_reaction(extractions)
        puts "change reaction" if DEBUG
        puts apologetic(change_prompt(extractions))
        @utterances << get_input
        utterance = @utterances.last
        answer = Util.extract_yes_no(utterance)
        next_extractions = extract(utterance, extractions.keys, false)#.select{|var, extraction| extraction.confidence > @change_threshold}

        # determines what selections are they trying to correct to
        selections = nil
        if answer == 'no'
            rejection_likelihood(extractions, answer.confidence)
            selections = next_extractions.select{|var, extraction| extraction != extractions[var]}
            increase_likelihood(selections)
        else
            if answer == 'yes'
                selections = extractions
                confirmation_likelihood(selections, answer.confidence)
            end
            # does this comparison work?
            if extractions == next_extractions
                selections = extractions
                confirmation_likelihood(selections, next_extractions.values.map(&:confidence).min)
            end
        end

        p selections if DEBUG

        # determines what to do with these selections
        if selections == nil
            puts apologetic(dont_understand_prompt)
            # TODO: slightly increase next_extractions_hash.likelihood
        else
            confident_hash = selections.select{|var, extraction| p extraction.confidence if DEBUG; extraction.confidence >= @select_threshold}
            maybe_hash = selections.select{|var, extraction| p extraction.confidence if DEBUG; extraction.confidence >= @clarify_threshold}
            p confident_hash if DEBUG
            if confident_hash.size == selections.size
                selection_reaction(confident_hash)
            elsif confident_hash.size > 0
                did_you_say_reaction(confident_hash)
            elsif maybe_hash.size > 0
                did_you_say_reaction(maybe_hash)
            else
                puts apologetic(dont_understand_prompt)
                # TODO: slightly increase next_extractions_hash.likelihood
            end
        end
    end

    # logic for this is made simpler by the simpler_group method
    def change_prompt(extractions)
        return "Were you trying to change #{extractions.keys.first.name} to #{Util.english_list(extractions.values.first)}?"
    end

    # logic for this is made simpler by the simpler_group method
    def did_you_say_prompt(extractions)
        if extractions.size == 1
            "Did you say #{Util.english_list(extractions.values.first)} for the #{extractions.keys.first.name}?"
        else
            "Did you say #{Util.english_list(extractions.values.map{|x| x.first})} for the #{Util.english_list(extractions.keys.map(&:name))}?"
        end
    end

    # same format as change_reaction
    def did_you_say_reaction(extractions)
        puts "did you say reaction" if DEBUG
        puts apologetic(did_you_say_prompt(extractions))
        @utterances << get_input
        utterance = @utterances.last
        answer = Util.extract_yes_no(utterance)
        next_extractions = extract(utterance, extractions.keys, false)#.select{|var, extraction| extraction.confidence > @change_threshold}

        # determines what selections are they trying to correct to
        selections = nil
        if answer == 'no'
            rejection_likelihood(extractions, answer.confidence)
            selections = next_extractions.select{|var, extraction| extraction != extractions[var]}
            increase_likelihood(selections)
        else
            if answer == 'yes'
                selections = extractions
                confirmation_likelihood(selections, answer.confidence)
            end
            # does this comparison work?
            if extractions == next_extractions
                selections = extractions
                confirmation_likelihood(selections, next_extractions.values.map(&:confidence).min)
            end
        end

        p selections if DEBUG

        # determines what to do with these selections
        if selections == nil
            puts apologetic(dont_understand_prompt)
            # TODO: slightly increase next_extractions_hash.likelihood
        else
            confident_hash = selections.select{|var, extraction| p extraction.confidence if DEBUG; extraction.confidence >= @select_threshold}
            maybe_hash = selections.select{|var, extraction| p extraction.confidence if DEBUG; extraction.confidence >= @clarify_threshold}
            p confident_hash if DEBUG
            if confident_hash.size == selections.size
                selection_reaction(confident_hash)
            elsif confident_hash.size > 0
                did_you_say_reaction(confident_hash)
            elsif maybe_hash.size > 0
                did_you_say_reaction(maybe_hash)
            else
                puts apologetic(dont_understand_prompt)
                # TODO: slightly increase next_extractions_hash.likelihood
            end
        end
    end

    # when overlapped, increase probability of both values in both variables (or could be more than 2), but not as big an increase (for n overlap, could divide by n)

    # replacements: look for "change", "actually", "replace", etc. and name of variable in selections
    # coder will need to be able to put in synonyms for name of variable
    def extract_change(utterance, variables)
        change_hash = {}
        variables.each do |variable|
            if utterance.include? variable.name && !(utterance | Util.change_set).empty?
                extractions = variable.extract(utterance)
                # TODO: make threshold also consider confidence in variable.name and change_set
                if !extractions.empty? && extractions.confidence >= change_threshold
                    change_hash[variable] = extractions
                end
            end
        end
        return change_hash
    end

    def rejection_likelihood(extractions, confidence)
        extractions.each do |variable, extraction|
            extraction.each do |value|
                #variable.prob_mass += extraction.likelihood * confidence
                value.confidence -= confidence
            end
        end
    end

    def increase_likelihood(extractions)
        extractions.each do |variable, extraction|
            extraction.each do |value|
                #variable.prob_mass += extraction.likelihood * confidence
                value.confidence += value.confidence / 2
            end
        end
    end

    def confirmation_likelihood(extractions, confidence)
        extractions.each do |variable, extraction|
            extraction.each do |value|
                #variable.prob_mass += extraction.likelihood * confidence
                value.confidence += value.confidence * confidence
            end
        end
    end

    def escape(utterance)
        puts "escape" if DEBUG
        false
    end

    def final_selection_reaction
    end

    def apologetic(prompt)
        @apologies += 1
        if @apologies < 2
            prompt
        else
            #puts Util.sorry_words[@repetitions % Util.sorry_words.size].capitalize + ', ' + prompt[0].downcase + prompt[1..-1]
            Util.sorry_words[(@apologies - 2) % Util.sorry_words.size].capitalize + ', ' + prompt
        end
    end
end

# TODO: when extracting multiple slots at a time, need to ignore overlapped values. e.g.:
# say cities for departure and destination are the same, and say
# the phrasings for destination are   [/#{value}/, /from #{value}/]
# and the phrasings for departure are [/#{value}/, /to #{value}/]
# we ignore instances of /#{value}/ completely and only look for the ones with 'from' or 'to'
# and if it doesn't find anything, have a special disambiguation_response


# class SlotGroup ?
# is there a need for a tree class or will that just fall out of how you write it?
