require './DialogPlatform'

#TODO: airline

depart_var = Variable.new('departure', ['San Diego', 'San Francisco', 'Los Angeles', 'Sacramento'])
depart_slot = Slot.new(depart_var, ['Where would you like to depart from?', 'What\'s your departure?'])
def depart_var.phrasings(value)
    value = value.downcase #I completely 100% plan on changing this so it's not so ugly, I don't want coder to have to write this line at all... but haven't figured out best way to do it yet
    [/#{value}/, /from #{value}/]
end

#dest_var = Variable.new('destination', ['Miami', 'New York', 'Atlanta', 'Philadelphia'])
dest_var = Variable.new('destination', ['San Diego', 'San Francisco', 'Los Angeles', 'Sacramento'])
dest_slot = Slot.new(dest_var, ['What is your destination?'])
def dest_var.phrasings(value)
    value = value.downcase
    [/#{value}/, /to #{value}/]
end

# eventually we should add actual support for numbers, like a setting for: this variable's values are integers in the range [0,30]. But for now, I'm just doing something hacky
year_var = Variable.new('year', ['2014', '2015', '2016'])
month_var = Variable.new('month', ['january', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'])
day_var = Variable.new('day', (0..31).to_a.map{|x| x.to_s})
time_var = Variable.new('time of day', ['morning', 'afternoon', 'night'])
# TODO: put day_var back in
time_slot = MultiSlot.new([month_var, time_var], ['When are you flying?'], [year_var, month_var, time_var])

#TODO: seating class

#TODO: depending on the airline, may have specific seating number

#TODO in general: be able to look up things and give the user options, i.e. "There are no flights at this time" or "We have flights available for $500, $400 and $300". This could also mean designing a multi-slot that doesn't try to fill everything

while(true)
    #depart_slot.run
    #dest_slot.run
    time_slot.run
end
