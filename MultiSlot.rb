require './Util'
require './Input'
require './Variable'

DEBUG = false

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
        p @variable.values.map{|value| [value.confidence, value]} if DEBUG
        line = gets.chomp
        utterance = Utterance.new(line)
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
