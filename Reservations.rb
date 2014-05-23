require './DialogPlatform'

depart_var = Variable.new('departure', ['San Diego', 'San Francisco', 'Los Angeles', 'Sacramento'])
depart_slot = Slot.new(depart_var, ['Where would you like to depart from?', 'What\'s your departure?'])
#def Departure.phrasings(value)
#    [/^#{value}.$/, /from #{value}/]
#end

dest_var = Variable.new('destination', ['Miami', 'New York', 'Atlanta', 'Philadelphia'])
dest_slot = Slot.new(dest_var, ['What is your destination?'])
#def Destination.phrasings(value)
#    [
#end

while(true)
    depart_slot.run
    dest_slot.run
end
