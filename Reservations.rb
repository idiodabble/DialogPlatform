require './DialogPlatform'

depart_var = Variable.new('departure', ['San Diego', 'San Francisco', 'Los Angeles', 'Sacramento'])
depart_slot = Slot.new(depart_var, ['Where would you like to depart from?', 'What\'s your departure?'])

dest_var = Variable.new('destination', ['San Diego', 'San Francisco', 'Los Angeles', 'Sacramento'])
dest_slot = Slot.new(dest_var, ['What is your destination?'])

# eventually we should add actual support for numbers, like a setting for: this variable's values are integers in the range [0,30]. But for now, I'm just doing something hacky
year_var = Variable.new('year', ['2014', '2015', '2016'])
month_var = Variable.new('month', ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'])
day_var = Variable.new('day', (0..31).to_a.map{|x| x.to_s})
time_var = Variable.new('time of day', ['morning', 'afternoon', 'night'])
time_slot = MultiSlot.new([year_var, month_var, day_var, time_var], ['When are you flying?'], [month_var, day_var, time_var])

airline_var = Variable.new('airline', ['Delta', 'Southwest', 'American', 'United', 'Air Canada', 'JetBlue', 'Alaska'])
airline_slot = Slot.new(airline_var, ['Which airline do you want to fly?'])

while(true)
    depart_slot.run
    #dest_slot.run
    time_slot.run
    airline = airline_slot.run
    if airline != 'Delta'
# seat.run
    end
end
