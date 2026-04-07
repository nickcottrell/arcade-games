#!/usr/bin/env bash
# ============================================================
#  MADLIBS STORIES  --  100+ story templates
# ============================================================
#  Each story has:
#    STORY_TITLE[n]    - name announced on selection
#    STORY_PROMPTS[n]  - pipe-delimited word types
#    STORY_TEMPLATE[n] - text with {1}, {2}, etc. placeholders
# ============================================================

STORY_TITLE=()
STORY_PROMPTS=()
STORY_TEMPLATE=()

# ----------------------------------------------------------
# 1
STORY_TITLE+=("A Day at the Beach")
STORY_PROMPTS+=("adjective|noun|verb ending in -ing|animal|number|body part|liquid|exclamation")
STORY_TEMPLATE+=("It was a {1} day at the beach. I spread out my {2} on the sand and started {3}. A wild {4} ran past carrying {5} hotdogs. I felt my {6} tingling, so I jumped into a pool of {7}. \"{8}!\" I shouted as a wave knocked me over.")

# 2
STORY_TITLE+=("The Job Interview")
STORY_PROMPTS+=("adjective|job title|verb (past tense)|noun|celebrity name|article of clothing|number|adverb")
STORY_TEMPLATE+=("I arrived for my {1} job interview to become a {2}. The interviewer {3} and handed me a {4}. \"We loved your reference from {5},\" she said. I adjusted my {6} nervously. After {7} minutes of {8} sweating, I got the job.")

# 3
STORY_TITLE+=("Alien Encounter")
STORY_PROMPTS+=("planet name|adjective|noun (plural)|verb (past tense)|color|body part|sound|food")
STORY_TEMPLATE+=("The spaceship landed on {1}. A {2} alien emerged carrying a basket of {3}. It {4} toward me, glowing {5}. It pointed at my {6}, made a loud {7} noise, and offered me some {8}. I think we are friends now.")

# 4
STORY_TITLE+=("Cooking Disaster")
STORY_PROMPTS+=("celebrity chef|adjective|food|liquid|number|verb ending in -ing|noun|animal sound")
STORY_TEMPLATE+=("I was watching {1} on TV and decided to make a {2} {3}. I poured in a gallon of {4} and waited {5} minutes. The kitchen started {6} and a {7} flew out of the oven. It made a {8} noise and I ordered pizza instead.")

# 5
STORY_TITLE+=("The Haunted House")
STORY_PROMPTS+=("adjective|room in a house|noun|verb (past tense)|color|animal|number|exclamation")
STORY_TEMPLATE+=("The house was extremely {1}. I crept into the {2} and found a glowing {3}. Something {4} behind me. A {5} fog filled the room and a ghost shaped like a {6} appeared. It chased me for {7} minutes. \"{8}!\" I screamed and ran outside.")

# 6
STORY_TITLE+=("Superhero Origin")
STORY_PROMPTS+=("adjective|noun|verb (past tense)|superpower|color|article of clothing|villain name|body part")
STORY_TEMPLATE+=("I was just a {1} person until I touched the radioactive {2}. Lightning {3} and I gained the power of {4}. My skin turned {5} and my {6} became my cape. My nemesis, {7}, would never see my {8} coming.")

# 7
STORY_TITLE+=("School Field Trip")
STORY_PROMPTS+=("place|adjective|teacher name|noun (plural)|verb (past tense)|animal|food|adverb")
STORY_TEMPLATE+=("Our class went on a field trip to {1}. It was {2} and our teacher {3} lost the {4}. Someone {5} into a pond and found a {6}. For lunch we ate {7} and everyone {8} agreed it was the best trip ever.")

# 8
STORY_TITLE+=("The Royal Decree")
STORY_PROMPTS+=("silly name|adjective|noun|verb|number|article of clothing|animal (plural)|food")
STORY_TEMPLATE+=("King {1} stood before the {2} crowd. \"I hereby decree that every {3} must {4} exactly {5} times per day!\" He adjusted his {6} and released {7} into the throne room. Dinner that night was nothing but {8}.")

# 9
STORY_TITLE+=("Space Mission")
STORY_PROMPTS+=("astronaut name|adjective|planet|noun|verb (past tense)|number|color|sound")
STORY_TEMPLATE+=("Commander {1} piloted the {2} spacecraft toward {3}. The {4} alarm {5} and {6} warning lights turned {7}. Mission control heard a mysterious {8} and decided to cancel brunch.")

# 10
STORY_TITLE+=("Wedding Chaos")
STORY_PROMPTS+=("name|adjective|noun|verb (past tense)|animal|food|number|exclamation")
STORY_TEMPLATE+=("At {1}'s wedding, everything was {2}. The ring bearer dropped the {3} and the flower girl {4} down the aisle riding a {5}. The cake was made of {6} and collapsed after {7} seconds. The bride yelled \"{8}!\" and everyone clapped.")

# 11
STORY_TITLE+=("Pirates of the Bathtub")
STORY_PROMPTS+=("pirate name|adjective|noun|verb ending in -ing|body part|liquid|number|animal")
STORY_TEMPLATE+=("Captain {1} sailed the {2} rubber ducky across the bathtub. The {3} was their treasure. They spent hours {4} while their {5} got pruny. The water turned to {6} and {7} toy {8}s attacked from the drain.")

# 12
STORY_TITLE+=("The Gym")
STORY_PROMPTS+=("adjective|noun|number|verb ending in -ing|body part|celebrity name|food|adverb")
STORY_TEMPLATE+=("I walked into the {1} gym and picked up a {2}. After {3} reps of {4}, my {5} was on fire. {6} was on the treadmill eating {7}. I {8} pretended I knew what I was doing and went home.")

# 13
STORY_TITLE+=("Dinosaur Discovery")
STORY_PROMPTS+=("scientist name|adjective|dinosaur type|noun|verb (past tense)|color|food|number")
STORY_TEMPLATE+=("Dr. {1} made a {2} discovery. A living {3} was hiding behind a {4}! It {5} and turned {6}. They fed it some {7} and it grew {8} feet taller. National Geographic was not returning their calls.")

# 14
STORY_TITLE+=("The Magic Spell")
STORY_PROMPTS+=("wizard name|adjective|noun|verb|animal|color|body part|silly word")
STORY_TEMPLATE+=("{1} the {2} wizard raised the enchanted {3}. \"I command you to {4}!\" A {5} appeared in a puff of {6} smoke. It bit the wizard's {7} and said \"{8}\" before vanishing into thin air.")

# 15
STORY_TITLE+=("Camping Trip")
STORY_PROMPTS+=("name|adjective|noun|animal|verb (past tense)|food|number|sound")
STORY_TEMPLATE+=("{1} went on a {2} camping trip. They forgot the {3} but found a friendly {4}. It {5} by the campfire and they shared some {6}. At {7} AM they heard a loud {8} and decided hotels were better.")

# 16
STORY_TITLE+=("The Doctor Visit")
STORY_PROMPTS+=("doctor name|adjective|body part|noun|number|verb ending in -ing|liquid|color")
STORY_TEMPLATE+=("Dr. {1} looked at my {2} {3}. \"You seem to have swallowed a {4},\" she said. \"This happens about {5} times a year.\" She prescribed {6} and a glass of {7}. My face turned {8} with embarrassment.")

# 17
STORY_TITLE+=("Robot Butler")
STORY_PROMPTS+=("robot name|adjective|noun|verb (past tense)|food|number|article of clothing|sound")
STORY_TEMPLATE+=("My robot butler {1} was extremely {2}. I asked for a {3} and it {4} across the room. It brought me {5} instead. After {6} attempts, it put on my {7} and made a {8} noise. I returned it to the store.")

# 18
STORY_TITLE+=("The Concert")
STORY_PROMPTS+=("band name|adjective|noun|verb (past tense)|body part|number|animal|exclamation")
STORY_TEMPLATE+=("I went to see {1} live. The {2} crowd waved their {3}s in the air. The guitarist {4} so hard their {5} fell off. After {6} encores, a {7} ran across the stage. The crowd screamed \"{8}!\" and it was the best night ever.")

# 19
STORY_TITLE+=("Pizza Delivery")
STORY_PROMPTS+=("name|adjective|noun|number|vehicle type|verb (past tense)|food topping|animal")
STORY_TEMPLATE+=("{1} was a {2} pizza delivery person. They carried every pizza in a {3}. One night, {4} orders came in at once. They jumped in their {5} and {6} through traffic. The last pizza had {7} topping and was delivered to a {8}.")

# 20
STORY_TITLE+=("The Time Machine")
STORY_PROMPTS+=("year|adjective|noun|verb (past tense)|famous person|food|article of clothing|exclamation")
STORY_TEMPLATE+=("I traveled back to the year {1}. Everything was {2}. I tripped over a {3} and {4} into {5}. They offered me some {6} and complimented my {7}. \"{8}!\" I said, and accidentally pressed the return button.")

# 21
STORY_TITLE+=("Pet Store Mayhem")
STORY_PROMPTS+=("adjective|animal|noun|verb (past tense)|color|number|food|body part")
STORY_TEMPLATE+=("The {1} pet store had one {2} left. It was sitting on a {3} and it {4} when I got close. Its eyes were {5} and it had {6} legs. I fed it some {7} and it licked my {8}. I brought it home immediately.")

# 22
STORY_TITLE+=("The Talent Show")
STORY_PROMPTS+=("name|adjective|verb ending in -ing|noun|number|animal|sound|body part")
STORY_TEMPLATE+=("{1} entered the {2} talent show. Their act was {3} while balancing a {4} for {5} minutes. A {6} in the audience made a {7} noise and everyone looked away. {1} took a bow with their {8} and somehow won third place.")

# 23
STORY_TITLE+=("Museum Heist")
STORY_PROMPTS+=("thief name|adjective|noun|verb (past tense)|color|article of clothing|number|animal")
STORY_TEMPLATE+=("{1} planned a {2} museum heist. The target was a priceless {3}. They {4} past the {5} laser beams wearing nothing but a {6}. {7} guards were asleep. A security {8} spotted them and the whole plan fell apart.")

# 24
STORY_TITLE+=("Babysitting")
STORY_PROMPTS+=("name|adjective|number|noun|verb (past tense)|food|animal|exclamation")
STORY_TEMPLATE+=("{1} agreed to babysit the {2} kids. Within {3} minutes, a {4} was stuck to the ceiling. Someone {5} in the bathtub. The toddler ate an entire {6} and dressed the cat like a {7}. \"{8}!\" the parents said when they got home.")

# 25
STORY_TITLE+=("The Race")
STORY_PROMPTS+=("name|adjective|vehicle type|noun|verb (past tense)|animal|number|body part")
STORY_TEMPLATE+=("{1} entered the {2} race in their custom {3}. At the starting line, a {4} fell from the sky. They {5} around the first turn and nearly hit a {6}. After {7} laps, they crossed the finish line using only their {8}.")

# 26
STORY_TITLE+=("Science Fair")
STORY_PROMPTS+=("name|adjective|noun|liquid|verb (past tense)|color|number|animal")
STORY_TEMPLATE+=("{1} built a {2} volcano for the science fair. They filled it with {3} and {4}. It {5} and turned everything {6}. The judges gave it a {7} out of 10. A {8} ate the remaining evidence.")

# 27
STORY_TITLE+=("The Date")
STORY_PROMPTS+=("name|adjective|restaurant type|food|verb (past tense)|noun|body part|exclamation")
STORY_TEMPLATE+=("{1} went on a {2} first date at a {3} restaurant. They ordered the {4} special. The waiter {5} and dropped a {6} on the table. My date touched their {7} nervously. \"{8},\" I said. There was no second date.")

# 28
STORY_TITLE+=("Treasure Map")
STORY_PROMPTS+=("name|adjective|noun|number|verb ending in -ing|animal|food|color")
STORY_TEMPLATE+=("{1} found a {2} treasure map behind a {3}. It said to walk {4} paces while {5}. A {6} was guarding the spot. The treasure was just a box of {7} wrapped in {8} paper. Still totally worth it.")

# 29
STORY_TITLE+=("The Dentist")
STORY_PROMPTS+=("dentist name|adjective|noun|verb (past tense)|number|flavor|body part|sound")
STORY_TEMPLATE+=("Dr. {1} peered into my {2} mouth. \"You have a {3} stuck in there,\" she {4}. It took {5} minutes to remove. The rinse tasted like {6}. My {7} was sore and I made a {8} noise all the way home.")

# 30
STORY_TITLE+=("The Zoo Escape")
STORY_PROMPTS+=("animal|adjective|noun|verb (past tense)|name|food|number|vehicle type")
STORY_TEMPLATE+=("A {1} escaped from the {2} zoo. It stole a {3} and {4} down Main Street. Zookeeper {5} chased it with a bag of {6}. After {7} blocks, they caught it hiding in a {8}. The mayor was not amused.")

# 31
STORY_TITLE+=("Grandma's House")
STORY_PROMPTS+=("adjective|food|noun|verb (past tense)|number|animal|body part|exclamation")
STORY_TEMPLATE+=("Grandma's house smelled {1}. She was baking {2} and knitting a {3}. She {4} when I walked in and pinched my cheeks {5} times. Her pet {6} bit my {7}. \"{8}!\" she said. \"That means it likes you.\"")

# 32
STORY_TITLE+=("The Substitute Teacher")
STORY_PROMPTS+=("silly name|adjective|noun|verb (past tense)|animal|subject|number|exclamation")
STORY_TEMPLATE+=("Our substitute teacher was Mr. {1}. He was very {2} and brought a {3} to class. He {4} on the desk and said his assistant was a trained {5}. For {6} class, we had to count to {7}. \"{8}!\" he shouted when the bell rang.")

# 33
STORY_TITLE+=("Amusement Park")
STORY_PROMPTS+=("adjective|ride name|noun|verb (past tense)|color|food|number|body part")
STORY_TEMPLATE+=("The {1} amusement park had a new ride called The {2}. You had to hold a {3} the whole time. I {4} and turned {5}. The only snack was deep-fried {6}. I rode it {7} more times until my {8} went numb.")

# 34
STORY_TITLE+=("Moving Day")
STORY_PROMPTS+=("adjective|noun|number|verb (past tense)|animal|food|body part|exclamation")
STORY_TEMPLATE+=("Moving day was {1}. The first box contained nothing but {2}s. It took {3} trips up the stairs. I {4} and dropped everything. A {5} had moved into the closet. For dinner we had {6} on the floor. My {7} ached. \"{8},\" I whispered, never again.")

# 35
STORY_TITLE+=("The Commercial")
STORY_PROMPTS+=("product name|adjective|verb|noun|number|celebrity name|body part|adverb")
STORY_TEMPLATE+=("Introducing {1}! The {2} way to {3} your {4}! Order in the next {5} minutes and {6} will personally massage your {7}! Call now! Operators are standing {8}!")

# 36
STORY_TITLE+=("Snowstorm")
STORY_PROMPTS+=("adjective|noun|number|verb (past tense)|animal|food|article of clothing|body part")
STORY_TEMPLATE+=("The {1} snowstorm buried the {2} in {3} feet of snow. We {4} outside and built a {5} out of ice. For warmth we ate frozen {6}. My {7} was soaked and my {8} turned blue. School was canceled and it was glorious.")

# 37
STORY_TITLE+=("The Magician")
STORY_PROMPTS+=("magician name|adjective|noun|animal|verb (past tense)|number|food|exclamation")
STORY_TEMPLATE+=("The Amazing {1} performed a {2} trick. They pulled a {3} out of a hat, then made a {4} appear. The audience {5} in disbelief. For the finale, {6} doves turned into {7}. \"{8}!\" the crowd roared.")

# 38
STORY_TITLE+=("Traffic Jam")
STORY_PROMPTS+=("adjective|vehicle type|number|verb ending in -ing|animal|food|song title|body part")
STORY_TEMPLATE+=("I was stuck in a {1} traffic jam in my {2} for {3} hours. The person next to me was {4}. A {5} crossed the highway carrying {6}. I blasted {7} on the radio and drummed on my {8} until traffic moved.")

# 39
STORY_TITLE+=("The Invention")
STORY_PROMPTS+=("inventor name|adjective|noun|verb|number|body part|food|sound")
STORY_TEMPLATE+=("{1} invented a {2} machine that could {3} any {4}. It only cost {5} dollars. The side effect was your {6} would smell like {7}. It made a constant {8} sound. Investors were not interested.")

# 40
STORY_TITLE+=("The Election")
STORY_PROMPTS+=("silly name|adjective|noun|verb|animal|food|number|article of clothing")
STORY_TEMPLATE+=("{1} ran for class president on a {2} platform. Their slogan was \"A {3} in every locker!\" They promised to {4} every Friday. Their running mate was a {5}. Free {6} for everyone! They won by {7} votes and wore a victory {8}.")

# 41
STORY_TITLE+=("The Fishing Trip")
STORY_PROMPTS+=("name|adjective|body of water|noun|verb (past tense)|animal|number|food")
STORY_TEMPLATE+=("{1} went on a {2} fishing trip at Lake {3}. They used a {4} as bait. Something {5} on the line. It was a giant {6} weighing {7} pounds. They threw it back and ate {8} for dinner instead.")

# 42
STORY_TITLE+=("Hotel Room")
STORY_PROMPTS+=("adjective|number|noun|verb (past tense)|animal|food|liquid|exclamation")
STORY_TEMPLATE+=("The {1} hotel room was on the {2}th floor. Under the bed was a {3}. I {4} the front desk but they sent up a {5} instead of help. Room service delivered {6} covered in {7}. \"{8}!\" I wrote in the review.")

# 43
STORY_TITLE+=("The Marathon")
STORY_PROMPTS+=("name|adjective|noun|verb (past tense)|animal|number|body part|food")
STORY_TEMPLATE+=("{1} signed up for a {2} marathon. At mile one, they lost a {3}. They {4} past a cheering {5}. By mile {6}, their {7} was completely numb. The finish line had free {8} and it was the only reason they kept going.")

# 44
STORY_TITLE+=("Pirate Ship")
STORY_PROMPTS+=("pirate name|adjective|ocean|noun|verb (past tense)|animal|number|food")
STORY_TEMPLATE+=("Captain {1} sailed the {2} seas of the {3}. The crew found a {4} floating in the water. They {5} with excitement. A {6} climbed aboard. After {7} days at sea, all that was left to eat was {8}. Mutiny was brewing.")

# 45
STORY_TITLE+=("School Lunch")
STORY_PROMPTS+=("adjective|food|color|noun|verb (past tense)|name|animal|sound")
STORY_TEMPLATE+=("The {1} school lunch was {2} again. It was {3} and had a {4} sticking out of it. I {5} and pushed it toward {6}. Even the cafeteria {7} would not eat it. My stomach made a {8} noise for the rest of the day.")

# 46
STORY_TITLE+=("The Haunted Carnival")
STORY_PROMPTS+=("adjective|noun|verb ending in -ing|clown name|color|animal|number|exclamation")
STORY_TEMPLATE+=("The {1} carnival appeared overnight. Every {2} was {3}. A clown named {4} had {5} teeth and rode a {6}. I won {7} goldfish at the ring toss. \"{8}!\" the clown whispered, and the carnival vanished by morning.")

# 47
STORY_TITLE+=("New Phone")
STORY_PROMPTS+=("brand name|adjective|noun|verb (past tense)|number|body part|food|color")
STORY_TEMPLATE+=("I got the new {1} phone. It was {2} and came with a free {3}. I {4} it out of the box. It had {5} cameras and could scan your {6}. The first photo I took was of my {7}. The phone turned {8} and never turned on again.")

# 48
STORY_TITLE+=("The Library")
STORY_PROMPTS+=("adjective|book title|noun|verb (past tense)|name|animal|number|sound")
STORY_TEMPLATE+=("I went to the {1} library to find a book called {2}. Behind the shelf was a secret {3}. I {4} inside and found {5} reading to a circle of {6}s. The overdue fine was {7} dollars. The library made a {8} noise and I was asked to leave.")

# 49
STORY_TITLE+=("Garage Sale")
STORY_PROMPTS+=("adjective|noun|number|verb (past tense)|celebrity name|food|animal|exclamation")
STORY_TEMPLATE+=("The {1} garage sale had a vintage {2} for only {3} dollars. I {4} over to grab it. Turns out it belonged to {5}. It came with a side of {6} and a live {7}. \"{8}!\" the seller shouted. \"No returns!\"")

# 50
STORY_TITLE+=("Airplane Ride")
STORY_PROMPTS+=("adjective|destination|noun|verb (past tense)|name|food|number|body part")
STORY_TEMPLATE+=("The {1} flight to {2} was delayed. A {3} was on the runway. The pilot {4} over the intercom. The passenger next to me, {5}, ordered {6} from the drink cart. We hit {7} patches of turbulence and my {8} has never been the same.")

# 51
STORY_TITLE+=("The Sleepover")
STORY_PROMPTS+=("name|adjective|food|noun|verb (past tense)|animal|number|sound")
STORY_TEMPLATE+=("{1} threw a {2} sleepover. We ate {3} until someone threw a {4}. Things got wild when someone {5} and a {6} appeared at the window. We stayed up until {7} AM making {8} noises. Nobody actually slept.")

# 52
STORY_TITLE+=("The Park")
STORY_PROMPTS+=("adjective|noun|verb ending in -ing|animal|name|food|number|body part")
STORY_TEMPLATE+=("I took a {1} walk in the park. I sat on a {2} and started {3}. A {4} sat down next to me. {5} jogged past eating {6}. I stayed for {7} hours until my {8} fell asleep and I could not stand up.")

# 53
STORY_TITLE+=("Video Game Boss")
STORY_PROMPTS+=("boss name|adjective|weapon type|verb (past tense)|number|animal|food|exclamation")
STORY_TEMPLATE+=("The final boss was {1}, a {2} monster. I equipped my {3} and {4}. After {5} attempts, I summoned a {6} as backup. The boss dropped a legendary {7}. \"{8}!\" I screamed at 2 AM. My neighbors were not happy.")

# 54
STORY_TITLE+=("The Farm")
STORY_PROMPTS+=("farmer name|adjective|animal|noun|verb (past tense)|food|number|color")
STORY_TEMPLATE+=("Farmer {1} had a {2} farm. The prize {3} escaped and hid in the {4}. It {5} when anyone got close. The crops were all {6}. After {7} seasons of this, everything on the farm turned {8}. Farming is hard.")

# 55
STORY_TITLE+=("Birthday Party")
STORY_PROMPTS+=("name|number|adjective|noun|verb (past tense)|animal|food|exclamation")
STORY_TEMPLATE+=("{1} turned {2} years old. The {3} party had a bouncy {4}. Someone {5} into the cake. A {6} popped out of a gift box. The candles set the {7} on fire. \"{8}!\" everyone sang, slightly off-key.")

# 56
STORY_TITLE+=("The Barber")
STORY_PROMPTS+=("barber name|adjective|noun|verb (past tense)|color|celebrity name|body part|sound")
STORY_TEMPLATE+=("{1} the barber was known for {2} haircuts. They used a {3} instead of scissors. They {4} a little too much. My hair turned {5} and I looked like {6}. Even my {7} felt embarrassed. The chair made a {8} noise as I left in shame.")

# 57
STORY_TITLE+=("Space Station")
STORY_PROMPTS+=("astronaut name|adjective|noun|verb ending in -ing|food|number|animal|color")
STORY_TEMPLATE+=("Astronaut {1} floated through the {2} space station. A {3} was {4} in zero gravity. Lunch was freeze-dried {5}. They had been up here for {6} days. A {7} somehow got aboard and everything was tinted {8} from the nebula outside.")

# 58
STORY_TITLE+=("The Babys First Word")
STORY_PROMPTS+=("baby name|adjective|noun|verb (past tense)|food|animal|silly word|exclamation")
STORY_TEMPLATE+=("Little {1} stared at us with {2} eyes. They picked up a {3} and {4}. We had been feeding them {5} all morning. The family {6} leaned in close. The baby opened its mouth and said \"{7}.\" Grandma shouted \"{8}!\" and fainted.")

# 59
STORY_TITLE+=("Dance Competition")
STORY_PROMPTS+=("dancer name|adjective|dance style|noun|verb (past tense)|body part|number|animal")
STORY_TEMPLATE+=("{1} entered the {2} dance competition. Their signature move was the {3} while holding a {4}. The judges {5} in amazement. Their {6} moved at {7} miles per hour. Even the {8} in the audience was impressed.")

# 60
STORY_TITLE+=("The Lemonade Stand")
STORY_PROMPTS+=("name|adjective|liquid|noun|number|verb (past tense)|animal|food")
STORY_TEMPLATE+=("{1} opened a {2} lemonade stand. Instead of lemonade, they sold {3}. The sign was written on a {4}. In {5} minutes, a crowd formed. Someone {6} and a {7} drank an entire pitcher. The secret ingredient was {8}.")

# 61
STORY_TITLE+=("The Car Wash")
STORY_PROMPTS+=("adjective|vehicle type|liquid|noun|verb (past tense)|color|animal|number")
STORY_TEMPLATE+=("I took my {1} {2} to the car wash. Instead of water, they used {3}. A {4} got stuck in the machine. It {5} and my car came out {6}. A {7} was now living in my back seat. The whole thing cost {8} dollars.")

# 62
STORY_TITLE+=("Movie Night")
STORY_PROMPTS+=("movie title|adjective|noun|verb (past tense)|food|name|animal|exclamation")
STORY_TEMPLATE+=("We watched {1}, a {2} film about a {3} that {4}. We ate so much {5} that {6} got sick. The scariest part was when the {7} appeared. \"{8}!\" we all shouted. Nobody could sleep that night.")

# 63
STORY_TITLE+=("The Detective")
STORY_PROMPTS+=("detective name|adjective|noun|verb (past tense)|place|color|animal|food")
STORY_TEMPLATE+=("Detective {1} examined the {2} crime scene. The missing {3} had been {4} somewhere near the {5}. The only clue was a {6} stain. A {7} was the prime suspect. The trail led to a warehouse full of {8}. Case sort of solved.")

# 64
STORY_TITLE+=("The First Day of School")
STORY_PROMPTS+=("name|adjective|noun|verb (past tense)|food|teacher name|animal|number")
STORY_TEMPLATE+=("{1} was {2} on the first day of school. They brought a {3} for show and tell. At recess, they {4} and fell in the mud. Lunch was mystery {5}. Their teacher, {6}, had a pet {7} on their desk. By period {8}, they wanted to go home.")

# 65
STORY_TITLE+=("The Treehouse")
STORY_PROMPTS+=("adjective|noun|number|verb (past tense)|animal|food|name|exclamation")
STORY_TEMPLATE+=("We built a {1} treehouse out of old {2}s. It was {3} feet off the ground. We {4} the ladder up after us. A {5} moved in first. We stocked it with {6}. {7} tried to visit but we said the password was \"{8}\" and they could not guess it.")

# 66
STORY_TITLE+=("Cooking Class")
STORY_PROMPTS+=("chef name|adjective|food|verb (past tense)|liquid|number|noun|color")
STORY_TEMPLATE+=("Chef {1} started the {2} cooking class. Today we were making {3}. I {4} the ingredients and added too much {5}. After {6} minutes, a {7} caught fire. The smoke was {8}. Everyone got an A for effort.")

# 67
STORY_TITLE+=("The Pet Psychic")
STORY_PROMPTS+=("psychic name|adjective|animal|noun|verb ending in -ing|food|number|body part")
STORY_TEMPLATE+=("{1} claimed to be a {2} pet psychic. They stared at my {3} for a while. \"Your pet wants a new {4},\" they said. \"It dreams about {5} and eating {6}.\" The session cost {7} dollars. My pet licked its {8} the entire time.")

# 68
STORY_TITLE+=("The Parade")
STORY_PROMPTS+=("holiday name|adjective|noun|verb (past tense)|animal (plural)|color|number|food")
STORY_TEMPLATE+=("The {1} parade was {2}. Every float had a giant {3}. The marching band {4} completely off-beat. A herd of {5}s wore {6} hats. {7} balloons escaped into the sky. The grand finale was a cannon that shot {8} into the crowd.")

# 69
STORY_TITLE+=("Road Trip")
STORY_PROMPTS+=("name|adjective|destination|noun|verb (past tense)|food|number|animal")
STORY_TEMPLATE+=("{1} planned a {2} road trip to {3}. They packed nothing but a {4}. The GPS {5} and sent them the wrong way. They survived on gas station {6} for {7} days. A {8} rode shotgun for the last 50 miles.")

# 70
STORY_TITLE+=("The Fortune Teller")
STORY_PROMPTS+=("fortune teller name|adjective|noun|verb|celebrity name|food|number|body part")
STORY_TEMPLATE+=("{1} gazed into the {2} crystal ball. \"I see a {3} in your future. You will {4} with {5}. Your lucky food is {6}. In {7} days, your {8} will tingle. That will be twelve dollars.\"")

# 71
STORY_TITLE+=("Laundry Day")
STORY_PROMPTS+=("adjective|article of clothing|noun|verb (past tense)|color|number|animal|food")
STORY_TEMPLATE+=("It was {1} laundry day. My favorite {2} was missing. I found a {3} in the dryer. Everything {4} and turned {5}. After {6} loads, a {7} crawled out of the machine. I gave up and ate {8}.")

# 72
STORY_TITLE+=("The News Report")
STORY_PROMPTS+=("anchor name|adjective|noun|verb (past tense)|place|animal|number|food")
STORY_TEMPLATE+=("\"Good evening, I am {1}. A {2} {3} has {4} near the {5}. Witnesses say a {6} was involved. {7} people were mildly inconvenienced. In other news, the price of {8} has skyrocketed. Back to you, Jim.\"")

# 73
STORY_TITLE+=("The Elevator")
STORY_PROMPTS+=("adjective|number|noun|name|verb (past tense)|animal|food|sound")
STORY_TEMPLATE+=("The {1} elevator stopped between floors {2} and 13. A {3} rolled across the floor. {4} {5} and pressed all the buttons. Someone's emotional support {6} was panicking. We shared a stick of {7}. The elevator made a {8} sound and finally moved.")

# 74
STORY_TITLE+=("The Weather Report")
STORY_PROMPTS+=("weather person name|adjective|noun|number|verb ending in -ing|liquid|animal|food")
STORY_TEMPLATE+=("{1} pointed at the {2} weather map. \"A front of {3}s is moving in at {4} miles per hour. Expect heavy {5} with a chance of {6}. If you own a {7}, bring it inside. Pack a lunch of {8}. This could last all week.\"")

# 75
STORY_TITLE+=("The Spelling Bee")
STORY_PROMPTS+=("name|adjective|silly word|verb (past tense)|noun|number|body part|exclamation")
STORY_TEMPLATE+=("{1} was the {2} favorite to win. The final word was \"{3}.\" They {4}, adjusted their {5}, and took {6} deep breaths. Their {7} was trembling. They spelled it wrong. \"{8}!\" the audience gasped. The runner-up fainted.")

# 76
STORY_TITLE+=("The Bakery")
STORY_PROMPTS+=("baker name|adjective|food|noun|verb (past tense)|color|number|animal")
STORY_TEMPLATE+=("{1}'s bakery was famous for {2} {3}. The secret ingredient was a crushed {4}. One batch {5} and turned {6}. They made {7} dozen anyway. A {8} broke in overnight and ate everything. The five-star review still came through.")

# 77
STORY_TITLE+=("Summer Camp")
STORY_PROMPTS+=("camp name|adjective|noun|verb (past tense)|animal|food|number|body part")
STORY_TEMPLATE+=("Camp {1} was the most {2} place on earth. Every cabin had a {3} hanging from the ceiling. The counselor {4} at orientation. A {5} was the camp mascot. For every meal we ate {6}. After {7} days, my {8} was sunburned and I was homesick.")

# 78
STORY_TITLE+=("The Plumber")
STORY_PROMPTS+=("plumber name|adjective|noun|verb (past tense)|liquid|animal|number|food")
STORY_TEMPLATE+=("{1} the plumber arrived looking {2}. A {3} was clogging the pipes. They {4} under the sink. Instead of water, {5} came out. A {6} was living in the drain. The bill was {7} dollars. They left behind a {8} as a tip.")

# 79
STORY_TITLE+=("The Auction")
STORY_PROMPTS+=("adjective|noun|number|celebrity name|verb (past tense)|animal|food|exclamation")
STORY_TEMPLATE+=("The {1} auction featured a rare {2}. Bidding started at {3} dollars. {4} {5} and raised their paddle. Someone counter-bid with a live {6}. The gavel came down on a crate of {7}. \"{8}!\" the auctioneer cried. Sold!")

# 80
STORY_TITLE+=("The Safari")
STORY_PROMPTS+=("name|adjective|animal|noun|verb (past tense)|color|number|food")
STORY_TEMPLATE+=("{1} went on a {2} safari. They spotted a {3} hiding behind a {4}. It {5} and changed to {6}. The guide said it happens about {7} times a year. For lunch they grilled {8} over an open fire. Nature is weird.")

# 81
STORY_TITLE+=("The Mailman")
STORY_PROMPTS+=("mailman name|adjective|noun|verb (past tense)|animal|number|food|body part")
STORY_TEMPLATE+=("{1} was the most {2} mail carrier in town. One day, a {3} arrived. They {4} it open and a {5} jumped out. It chased them for {6} blocks. They dropped a package of {7}. Their {8} was never the same after that route.")

# 82
STORY_TITLE+=("The Podcast")
STORY_PROMPTS+=("podcast name|adjective|noun|verb ending in -ing|celebrity name|food|number|sound")
STORY_TEMPLATE+=("Welcome to {1}, the most {2} podcast about {3}s. Today we are {4} with special guest {5}. Our sponsor is artisanal {6}. This episode has been downloaded {7} times. Please rate and subscribe. The closing jingle goes {8}.")

# 83
STORY_TITLE+=("The Neighbor")
STORY_PROMPTS+=("neighbor name|adjective|noun|verb (past tense)|animal (plural)|number|food|sound")
STORY_TEMPLATE+=("My neighbor {1} was extremely {2}. They kept a giant {3} in their yard. Yesterday, they {4} over the fence. Their {5}s escaped into my garden {6} times this month. They left a plate of {7} on my doorstep that made a {8} noise.")

# 84
STORY_TITLE+=("The Lifeguard")
STORY_PROMPTS+=("lifeguard name|adjective|noun|verb (past tense)|animal|food|number|body part")
STORY_TEMPLATE+=("Lifeguard {1} was extremely {2}. They rescued a {3} from the deep end. Someone {4} off the high dive and landed on a {5}. The snack bar only sold {6}. After {7} hours in the sun, my {8} looked like a lobster.")

# 85
STORY_TITLE+=("The Inventor")
STORY_PROMPTS+=("inventor name|adjective|noun|verb|body part|food|number|animal")
STORY_TEMPLATE+=("{1} invented a {2} device that could {3} any {4} with your {5}. It was powered by {6} and weighed {7} pounds. The prototype escaped and became a {8}. The patent is still pending.")

# 86
STORY_TITLE+=("The Choir")
STORY_PROMPTS+=("choir name|adjective|song title|verb (past tense)|animal|number|food|body part")
STORY_TEMPLATE+=("The {1} choir attempted a {2} rendition of {3}. The soprano {4} so hard a {5} flew out of the rafters. All {6} members were eating {7} between verses. The conductor waved their {8} wildly. Standing ovation anyway.")

# 87
STORY_TITLE+=("The Mechanic")
STORY_PROMPTS+=("mechanic name|adjective|vehicle type|noun|verb (past tense)|animal|number|liquid")
STORY_TEMPLATE+=("{1} looked at my {2} {3}. \"Your {4} is completely {5},\" they said. A {6} was nesting under the hood. The repair would take {7} hours and required three gallons of {8}. I took the bus home.")

# 88
STORY_TITLE+=("The Costume Party")
STORY_PROMPTS+=("name|adjective|celebrity name|noun|verb (past tense)|animal|food|exclamation")
STORY_TEMPLATE+=("{1} showed up to the {2} costume party dressed as {3}. They were carrying a {4}. Someone {5} into the punch bowl. The DJ was a {6} in a top hat. The buffet was nothing but {7}. \"{8}!\" everyone shouted at midnight.")

# 89
STORY_TITLE+=("The Coach")
STORY_PROMPTS+=("coach name|adjective|sport|noun|verb (past tense)|number|animal|body part")
STORY_TEMPLATE+=("Coach {1} gave a {2} speech before the big {3} game. \"Remember your {4}!\" they {5}. After {6} quarters, a {7} ran onto the field. The winning play involved someone's {8}. The trophy was shaped like a toilet.")

# 90
STORY_TITLE+=("The Cruise Ship")
STORY_PROMPTS+=("ship name|adjective|noun|verb (past tense)|food|animal|number|body part")
STORY_TEMPLATE+=("The SS {1} was the most {2} cruise ship ever. Every cabin had a {3}. The captain {4} during the welcome dinner. The buffet had {5} and live {6}. On day {7}, my {8} got stuck in a deck chair. I still gave it five stars.")

# 91
STORY_TITLE+=("The Photography Class")
STORY_PROMPTS+=("adjective|noun|verb (past tense)|animal|color|number|food|body part")
STORY_TEMPLATE+=("My {1} photography class had us photograph a {2}. I {3} the shutter and captured a {4} in mid-air. The print came out {5}. The professor gave me a {6} out of 10. My best work is still a close-up of {7} on a {8}.")

# 92
STORY_TITLE+=("The Escape Room")
STORY_PROMPTS+=("adjective|noun|number|verb (past tense)|animal|food|body part|exclamation")
STORY_TEMPLATE+=("The {1} escape room had a locked {2}. We had {3} minutes. Someone {4} the clue across the room. A {5} was part of the puzzle. The final code involved counting {6}s. My {7} was sore from crawling. \"{8}!\" we yelled with 3 seconds left.")

# 93
STORY_TITLE+=("The Car Pool")
STORY_PROMPTS+=("name|adjective|vehicle type|food|verb ending in -ing|animal|number|sound")
STORY_TEMPLATE+=("{1} ran a {2} car pool in a {3}. Everyone had to bring {4}. No {5} in the vehicle. Somehow a {6} got in the trunk. We were late {7} times this week. The horn made a {8} noise and everyone stared at us.")

# 94
STORY_TITLE+=("The Science Lab")
STORY_PROMPTS+=("professor name|adjective|liquid|noun|verb (past tense)|color|animal|number")
STORY_TEMPLATE+=("Professor {1} mixed the {2} chemicals. The {3} reacted with the {4} and {5}. Everything turned {6}. A {7} appeared in the beaker. The university revoked {8} of their grants immediately.")

# 95
STORY_TITLE+=("The Food Truck")
STORY_PROMPTS+=("truck name|adjective|food|noun|verb (past tense)|celebrity name|number|animal")
STORY_TEMPLATE+=("The {1} food truck served {2} {3}. The secret was a special {4} they {5} into every order. Even {6} was a regular. The line was {7} people deep. A {8} waited patiently for scraps. Health inspector gave it a shrug.")

# 96
STORY_TITLE+=("The Dentist Office Waiting Room")
STORY_PROMPTS+=("adjective|noun|number|verb ending in -ing|animal|food|magazine title|sound")
STORY_TEMPLATE+=("The {1} waiting room had a fish tank with one {2}. I sat there for {3} minutes, {4}. A kid with a toy {5} threw {6} at me. I read a magazine called {7} Monthly. My tooth made a {8} noise and I almost left.")

# 97
STORY_TITLE+=("The App")
STORY_PROMPTS+=("app name|adjective|verb|noun|number|celebrity name|body part|food")
STORY_TEMPLATE+=("I downloaded {1}, the {2} new app that lets you {3} any {4}. It had {5} stars. {6} endorsed it on TV. Side effects include a tingling {7}. In-app purchases include premium {8}. I deleted it after one hour.")

# 98
STORY_TITLE+=("The Pillow Fight")
STORY_PROMPTS+=("name|adjective|noun|verb (past tense)|number|animal|body part|exclamation")
STORY_TEMPLATE+=("{1} started a {2} pillow fight. Someone stuffed a {3} inside theirs. I {4} across the room. After {5} minutes, feathers covered the {6}. My {7} was sore. \"{8}!\" Mom yelled from downstairs. We blamed the cat.")

# 99
STORY_TITLE+=("The Drive-Through")
STORY_PROMPTS+=("restaurant name|adjective|food|noun|verb (past tense)|animal|number|liquid")
STORY_TEMPLATE+=("The {1} drive-through was extremely {2}. I ordered a {3} with extra {4}. The speaker {5} and a {6} answered. They got my order wrong {7} times. The drink was pure {8}. I ate it in the parking lot and questioned my choices.")

# 100
STORY_TITLE+=("The Yoga Class")
STORY_PROMPTS+=("instructor name|adjective|animal|body part|verb (past tense)|number|food|sound")
STORY_TEMPLATE+=("Instructor {1} led a {2} yoga session. \"Now become the {3},\" they whispered. My {4} {5} and would not unbend. After {6} poses, I needed a {7}. The person behind me made a {8} noise. Namaste, I guess.")

# 101
STORY_TITLE+=("The Cab Ride")
STORY_PROMPTS+=("driver name|adjective|noun|verb (past tense)|place|animal|number|food")
STORY_TEMPLATE+=("My cab driver {1} was {2}. A {3} was duct-taped to the dashboard. They {4} through {5}. A {6} was in the front seat. The meter hit {7} dollars. They offered me some {8} as an apology. Five stars for entertainment.")

# 102
STORY_TITLE+=("The Treehouse Club")
STORY_PROMPTS+=("club name|adjective|noun|number|verb ending in -ing|food|animal|exclamation")
STORY_TEMPLATE+=("Welcome to the {1} club. Our {2} treehouse has one rule: no {3}s allowed. We have {4} members. The initiation involves {5} for one full minute. Dues are paid in {6}. Our mascot is a {7}. The password is \"{8}\" and we will never change it.")

# 103
STORY_TITLE+=("The Roller Coaster")
STORY_PROMPTS+=("ride name|adjective|number|verb (past tense)|body part|animal|food|exclamation")
STORY_TEMPLATE+=("The {1} roller coaster was the most {2} ride in the park. It had {3} loops. I {4} and grabbed my {5}. A {6} was sitting in the seat next to me. At the top, I dropped my {7}. \"{8}!\" I screamed the entire way down.")

# 104
STORY_TITLE+=("The Text Message")
STORY_PROMPTS+=("name|adjective|noun|verb (past tense)|animal|food|number|body part")
STORY_TEMPLATE+=("I accidentally texted {1} a {2} message about a {3}. They {4} immediately. The autocorrect changed everything to {5} and {6}. I sent {7} follow-up texts. My {8} was shaking. They still have not replied.")

# 105
STORY_TITLE+=("The Yard Sale")
STORY_PROMPTS+=("adjective|noun|number|name|verb (past tense)|food|animal|exclamation")
STORY_TEMPLATE+=("My {1} yard sale featured a genuine {2} for {3} cents. {4} {5} over to inspect it. I threw in a free {6}. A {7} knocked over the display table. \"{8}!\" everyone yelled. Total earnings: four dollars and a button.")

# 106
STORY_TITLE+=("The Ghost Story")
STORY_PROMPTS+=("name|adjective|place|noun|verb (past tense)|color|animal|sound")
STORY_TEMPLATE+=("Legend says {1} haunts the {2} {3}. They carry a glowing {4}. One night, they {5} through the walls. A {6} mist filled the room. Even the {7} ran away. If you listen closely, you can hear a faint {8} to this day.")

# 107
STORY_TITLE+=("The Picnic")
STORY_PROMPTS+=("name|adjective|food|noun|verb (past tense)|animal (plural)|number|body part")
STORY_TEMPLATE+=("{1} planned a {2} picnic. They brought {3} and a checkered {4}. A swarm of {5} {6} every crumb. {7} ants marched across my {8}. We packed up after ten minutes. Indoor dining was invented for a reason.")

# 108
STORY_TITLE+=("The New Year Party")
STORY_PROMPTS+=("adjective|noun|verb (past tense)|name|food|number|animal|exclamation")
STORY_TEMPLATE+=("The {1} New Year party started with a bang. A {2} {3} across the room. {4} showed up with a plate of {5}. At {6} seconds to midnight, a {7} jumped on the DJ booth. \"{8}!\" we all shouted. Best year yet, probably.")

# 109
STORY_TITLE+=("The Flea Market")
STORY_PROMPTS+=("adjective|noun|number|verb (past tense)|celebrity name|food|animal|color")
STORY_TEMPLATE+=("The {1} flea market had a suspicious {2} for {3} dollars. I {4} it carefully. The seller claimed it belonged to {5}. It came with a side of {6} and a small {7}. Everything was painted {8}. I bought it. No regrets. Some regrets.")

# 110
STORY_TITLE+=("The Subway")
STORY_PROMPTS+=("adjective|noun|verb ending in -ing|name|animal|food|number|sound")
STORY_TEMPLATE+=("The {1} subway was packed. Someone left a {2} on the seat. A person was {3} in the corner. {4} sat across from me with a {5} on a leash. It was eating {6}. We were stuck underground for {7} minutes. The intercom made a {8} noise. Nobody reacted.")

STORY_COUNT=${#STORY_TITLE[@]}
