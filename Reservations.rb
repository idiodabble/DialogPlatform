require './DialogPlatform'

Departure = Slot.new('departure', ['Where would you like to depart from?', 'What\'s your departure?'], ['San Diego', 'San Francisco', 'Los Angeles', 'Sacramento'])
#def Departure.phrasings(value)
#    [/^#{value}.$/, /from #{value}/]
#end

Destination = Slot.new('destination', ['What is your destination?'], ['Miami', 'New York', 'Atlanta', 'Philadelphia'])
#def Destination.phrasings(value)
#    [
#end

while(true)
    Departure.run
    Destination.run
end
