require './Slot'
require './MultiSlot'

# EasyDial
# A Ruby platform for creating new dialog systems
# Designed to let users easily make new dialog systems with a platform that is heavily modifiable, so it can be customized to the individual dialog system's needs.
# Author:: Daniel Steffee and Jeremy Hines

# Jeremy TODO LIST:

# 1. Make prefixes and suffixes work again
# 2. Add synonyms
# 3. Add multi-word prefixes

# Steff TODO list:

# 1. Make extract not change likelihoods
# 2. test change_reaction, then test MultiSlot with variables with max_selections higher than 1
# 3. create a default variable_name prefix of some sort

# 4. change the rejection/confirmation/increase likelihood methods?
# 5. Support for numbers?
# 6. Variable's default_value?
# 7. maybe replace @name_thresholds with name_threshold() methods?

# Bonus TODO list for if we have time:

# 1. Make a proper RDOC. For now, the description of the system in the writeup + comments should be enough
# 2. write a Platform class, higher than Slot or MultiSlot, that will take advantage of methods like preconditions and next_slot
# 3. be able to look up things and give the user options, i.e. "There are no flights at this time" or "We have flights available for $500, $400 and $300"

