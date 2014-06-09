require 'set'
require './Misc'
require './Util'

# Designed to let users easily make new dialog systems with a platform that is heavily modifiable, so it can be customized to the individual dialog system's needs.
# Author:: Daniel Steffee and Jeremy Hines

# Jeremy TODO LIST:

# 1. Bug:
    # In the time MultiSlot in Reservations, if you say
    # - January 2014
    # - No
    # - Afternoon of the 21st
    # - 21st
    # It sets 2 for the day instead of 21

    # also, maybe the same bug: why does it think I'm choosing 14 for my day when I type "January 7, 2014"? Shouldn't 7, an exact match, be better than 2014?

# 2. Treat San (0.1) Diego (0.1) differently from San (1) Diego (1)
# 3. Add synonyms
# 4. Write MultiSlot version of extract, which needs to detect overlaps (same values in different variables)

# also, do multi-word prefixes work?

# Steff TODO list:

# 1. Finish testing did_you_say_reaction, then port everything over to change_reaction
# 2. test MultiSlot with variables with max_selections higher than 1
# 3. create a default variable_name prefix of some sort

# 4. change the rejection/confirmation/increase likelihood methods?
# 5. maybe replace @name_thresholds with name_threshold() methods?

# Bonus TODO list for if we have time:

# 1. Make a proper RDOC. For now, the description of the system in the writeup + comments should be enough
# 2. write a Platform class, higher than Slot or MultiSlot, that will take advantage of methods like preconditions and next_slot
# 3. be able to look up things and give the user options, i.e. "There are no flights at this time" or "We have flights available for $500, $400 and $300"

DEBUG = true

class Slot
    # prompts: an array of possible prompts
    #    a prompt is what the system tells the user at the start of the slot
    #    such as 'Where would you like to depart from?'
    # extract_threshold: number between 0 and 1, user input will be accepted if confidence is above this threshold 
    # clarify_threshold: number between 0 and 1, clarification will be requested if confidence is above this threshold 
    #    and below extract_threshold. If confidence is below clarify_threshold, the run method will return false
    #    and let somebody else figure out what to do
    # utterances: array containing every utterance the user has said. An utterance is an array of Words
    def initialize(variable, prompts, extract_threshold = 0.6, clarify_threshold = 0.3)
        @variable = variable
        @prompts = prompts
        @extract_threshold = extract_threshold
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
            print "Selection confidence: " if DEBUG
            p @selection.confidence if DEBUG
            if @selection.confidence >= @extract_threshold
                break
            elsif @selection.confidence >= @clarify_threshold
                #TODO: need to increase likelihood of all extractions, not just top
                break if did_you_say_reaction
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

    # style question: keep parameters or keep class fields?
    def did_you_say_reaction
        puts apologetic(@variable.did_you_say_prompt(@selection))
        @utterances << get_input
        line = @utterances.last.line
        if Util.no_set.include? line
            rejection_likelihood(@selection) if @selection.size == 1
            puts "Oh, what did you mean?"
            @utterances << get_input
        elsif Util.no_set.find{|no_word| line[no_word] != nil} != nil
            rejection_likelihood(@selection) if @selection.size == 1
        elsif Util.yes_set.find{|no_word| line[no_word] != nil} != nil
            return true
        else
            repetition_likelihood(@extraction)
        end
        return false
    end

    # again, do something less dumb
    def rejection_likelihood(extractions)
        repetition_likelihood(@variable.values - extractions)
    end

    # style question: what to name the parameter?
    def repetition_likelihood(extractions)
        extractions.each{|extraction|
            # TODO: make this not dumb
            extraction.confidence += extraction.confidence
        }
    end

    # this is how the coder can escape the Slot, in case the user is trying to exit or jump elsewhere
    # TODO: create an example of escape in either Reservation.rb or a higher level class
    def escape(utterance, extractions)
        false
    end

    def extracted_nothing_prompt
        puts apologetic("I'm not sure what you said, could you repeat your response?")
    end

    def extracted_nothing_reaction
        extracted_nothing_prompt
        repetition_likelihood(@extraction)
        @utterances << get_input
    end

    def selection_reaction
        responses = @selection.map(&:response).compact
        # value specific responses
        responses.each{|response| puts response}
        # general variable response 
        puts @variable.response unless @variable.response.nil?
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
    def extract(utterance, variables)
        if(variables.length == 1) then # Single-slot extract
            return extract_single_slot(utterance, variables[0])
        else # Multi-slot extract
            return extract_multi_slot(utterance, variables)
        end
    end

    def extract_single_slot(utterance, variable)
        extractions = {}
        extraction = variable.extract(utterance)
        top_extraction = variable.top_extraction(extraction)
        extractions[variable] = top_extraction
        return extractions
    end

    # Checks all the slots and attempts to assign values to each
    # If there are overlaps that can't be resolved: return true 
    # and revert to default
    def extract_multi_slot(utterance, variables)
        # run all the varibles extract methods
        # make sure to know which words are used
        # if the words are overlapped, return false
        extractions = {}
        variables.each do |variable|
            extraction = variable.extract(utterance)
            top_extraction = variable.top_extraction(extraction)
            extractions[variable] = top_extraction
        end








        
        return extractions
    end

    # Checks to see if the any words are used by multiple slots
    def is_overlapping(extractions)
        top = Set.new
        extractions.each do |extract, value|
            return true if top.include? value
            top.add(value)
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
        answer = extract_yes_no(utterance)
        next_extractions = extract(utterance, extractions.keys)#.select{|var, extraction| extraction.confidence > @change_threshold}

        # determines what selections are they trying to correct to
        selections = nil
        if answer == 'no'
            rejection_likelihood(extractions, answer.confidence)
            #puts "YO YO YO YO YO"
            #p extractions
            #p next_extractions
            selections = next_extractions.select{|var, extraction| extraction != extractions[var]}
            #p selections
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

    def extract_yes_no(utterance)
        if utterance.size == 1
            word = utterance.first
            if Util.no_set.include? word
                return Value.new('no', word.confidence) 
            elsif Util.yes_set.include? word
                return Value.new('yes', word.confidence)
            end
        end
        no = utterance.find{|word| Util.no_set.include? word}
        yes = utterance.find{|word| Util.yes_set.include? word}
        if no && yes.nil?
            return Value.new('no', no.confidence / utterance.size)
        elsif no.nil? && yes
            return Value.new('yes', yes.confidence / utterance.size)
        end
        return Value.new('not found', 0)
    end

    # TODO: need to figure out which likelihoods need to change. Extractions? Extraction? Value?

    def rejection_likelihood(extractions, confidence)
        extractions.each do |variable, extraction|
            extraction.each do |value|
                #variable.prob_mass += extraction.likelihood * confidence
                p value
                p confidence
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
                p value.confidence
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
