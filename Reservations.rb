require './DialogPlatform'

#TODO: airline

depart_var = Variable.new('departure', ['San Diego', 'San Francisco', 'Los Angeles', 'Sacramento'])
depart_slot = Slot.new(depart_var, ['Where would you like to depart from?', 'What\'s your departure?'])
def depart_var.phrasings(value)
    value = value.value.downcase #I completely 100% plan on changing this so it's not so ugly, I don't want coder to have to write this line at all... but haven't figured out best way to do it yet
    [/#{value}/, /from #{value}/]
end

#dest_var = Variable.new('destination', ['Miami', 'New York', 'Atlanta', 'Philadelphia'])
dest_var = Variable.new('destination', ['San Diego', 'San Francisco', 'Los Angeles', 'Sacramento'])
dest_slot = Slot.new(dest_var, ['What is your destination?'])
def dest_var.phrasings(value)
    value = value.value.downcase
    [/#{value}/, /to #{value}/]
end

#TODO: time: month, day of month, time of day

#TODO: seating class

#TODO: depending on the airline, may have specific seating number

#TODO in general: be able to look up things and give the user options, i.e. "There are no flights at this time" or "We have flights available for $500, $400 and $300". This could also mean designing a multi-slot that doesn't try to fill everything

while(true)
    depart_slot.run
    dest_slot.run
end
