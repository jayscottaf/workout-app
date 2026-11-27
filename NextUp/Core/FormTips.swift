import Foundation

/// Short coaching cues shown on each exercise. Keyed by ExerciseDef id.
enum FormTips {
    static let byID: [String: [String]] = [
        // Chest
        "db_bench": [
            "Shoulder blades pinned back and down",
            "Lower to mid-chest, elbows about 45° from your sides",
            "Press up and slightly in, without clanking the bells",
        ],
        "bb_bench": [
            "Eyes under the bar, feet planted, shoulder blades tight",
            "Lower to mid-chest with elbows tucked about 45°",
            "Touch the chest lightly, don't bounce the bar off it",
        ],
        "machine_chest_press": [
            "Set the seat so handles line up with mid-chest",
            "Keep your back and head against the pad",
            "Stop just short of locking out, then lower slowly",
        ],
        "smith_bench": [
            "Set the bench so the bar lands on mid-chest",
            "Shoulder blades back and down, feet flat",
            "Lower under control, don't bounce off the chest",
        ],
        "pushup": [
            "Hands a bit wider than shoulders, body in a straight line",
            "Lower until your chest nearly touches the floor",
            "Don't let your hips sag or pike up",
        ],
        "incline_db_press": [
            "Bench at a low incline, about 30°",
            "Lower to the upper chest, elbows slightly tucked",
            "Keep your shoulders down, away from your ears",
        ],
        "incline_bb_press": [
            "Bench at a low incline, about 30°",
            "Lower the bar to your upper chest, below the collarbone",
            "Keep your butt on the bench as you press",
        ],
        "smith_incline": [
            "Set the bench so the bar lands on your upper chest",
            "Shoulder blades back and down the whole set",
            "Lower slowly and press without locking out hard",
        ],
        "cable_fly": [
            "Stagger your stance and lean slightly forward",
            "Keep a soft, fixed bend in your elbows",
            "Bring hands together in a hugging arc, not a press",
        ],
        "pec_deck": [
            "Set the seat so handles are at chest height",
            "Keep your back on the pad and chest up",
            "Squeeze together, then open slowly to a light stretch",
        ],
        "db_fly": [
            "Slight bend in the elbows, held the whole rep",
            "Lower in a wide arc until you feel a chest stretch",
            "Don't drop the bells too low or turn it into a press",
        ],

        // Triceps
        "pushdown": [
            "Elbows pinned to your sides",
            "Push down until arms are straight, then squeeze",
            "Don't lean over the bar or swing your shoulders",
        ],
        "one_arm_pulldown": [
            "Keep the working elbow tucked at your side",
            "Straighten the arm fully at the bottom",
            "Control the way up instead of letting it snap back",
        ],
        "tri_machine": [
            "Line your elbows up with the machine's pivot",
            "Keep your upper arms still on the pad",
            "Straighten fully, then return slowly",
        ],
        "db_overhead_ext": [
            "Hold one bell with both hands, arms overhead",
            "Elbows point forward and stay close to your head",
            "Lower behind your head for a full stretch",
        ],
        "cable_overhead_ext": [
            "Face away from the cable with a slight forward lean",
            "Keep elbows up and pointed forward",
            "Only the forearms move, straighten fully each rep",
        ],
        "ez_skullcrusher": [
            "Upper arms angled slightly back, not straight up",
            "Lower the bar toward your forehead or just behind",
            "Keep elbows from flaring out to the sides",
        ],
        "skullcrusher": [
            "Upper arms angled slightly back, not straight up",
            "Lower the bar toward your forehead or just behind",
            "Keep elbows narrow and the lowering slow",
        ],
        "bench_dip": [
            "Hands on the bench edge, fingers forward",
            "Keep your back close to the bench as you lower",
            "Lower until upper arms are about level, then press",
        ],
        "dip": [
            "Start at the top with arms straight and shoulders down",
            "Lower until upper arms are about level with the bars",
            "Stay tall for triceps, don't let shoulders roll forward",
        ],

        // Back
        "lat_pulldown": [
            "Thighs snug under the pad, chest up",
            "Pull the bar to your upper chest, elbows down",
            "Don't lean way back or yank with momentum",
        ],
        "pullup": [
            "Start from a full hang with shoulders engaged",
            "Pull your chest toward the bar, elbows down and back",
            "No kicking or swinging to get over the bar",
        ],
        "assisted_pullup": [
            "More weight means more help, so lower it over time",
            "Pull your chest toward the bar, elbows down",
            "Lower all the way to straight arms each rep",
        ],
        "cable_row": [
            "Sit tall with a slight bend in your knees",
            "Pull the handle to your belly, squeeze shoulder blades",
            "Don't rock your torso back and forth",
        ],
        "db_row": [
            "Brace on a bench with a flat back",
            "Pull the bell toward your hip, not your chest",
            "Keep your torso still, no twisting to lift it",
        ],
        "bb_row": [
            "Hinge forward with a flat back, knees soft",
            "Pull the bar to your lower ribs",
            "Hold your torso angle, don't stand up to finish",
        ],
        "chest_supported_row": [
            "Lie chest-down on a bench set to a low incline",
            "Pull the dumbbells toward your hips, elbows back",
            "Keep your chest on the pad the whole time",
        ],
        "tbar_row": [
            "Hinge with a flat back, chest over the bar",
            "Pull the handles to your upper stomach",
            "Squeeze shoulder blades, then lower with control",
        ],
        "inverted_row": [
            "Hang under a bar at hip height, body straight",
            "Pull your chest to the bar, squeeze shoulder blades",
            "Bend your knees to make it easier",
        ],
        "machine_row": [
            "Set the seat so handles are at mid-chest",
            "Chest on the pad, pull elbows back",
            "Squeeze the shoulder blades, then return slowly",
        ],
        "db_pullover": [
            "Lie across or along a bench, bell over your chest",
            "Keep a slight elbow bend and lower behind your head",
            "Go only as far as you can without arching your back",
        ],
        "straight_arm": [
            "Hinge slightly forward, arms nearly straight",
            "Sweep the bar down to your thighs",
            "Keep elbows still, don't turn it into a pushdown",
        ],
        "back_ext": [
            "Set the pad just below your hip bones",
            "Lower with a flat back, then rise to a straight line",
            "Stop at straight, don't arch past it at the top",
        ],
        "face_pull": [
            "Set the rope at about eye level",
            "Pull toward your face, hands ending beside your ears",
            "Keep elbows high and don't lean back",
        ],
        "reverse_fly": [
            "Hinge forward with a flat back",
            "Raise arms out wide with a soft elbow bend",
            "Use light weight and avoid swinging",
        ],
        "reverse_pec_deck": [
            "Face the pad, handles at shoulder height",
            "Sweep arms back wide, leading with the elbows",
            "Don't shrug, keep shoulders down",
        ],

        // Biceps
        "db_curl": [
            "Elbows stay at your sides the whole rep",
            "Turn palms up as you curl",
            "Lower slowly, no swinging the weight up",
        ],
        "bb_curl": [
            "Grip about shoulder width, elbows at your sides",
            "Curl without leaning back or using your hips",
            "Lower all the way down under control",
        ],
        "cable_curl": [
            "Stand close to the cable, elbows at your sides",
            "Curl up and squeeze at the top",
            "Keep tension on the way down, don't let it yank",
        ],
        "ez_preacher": [
            "Armpits snug against the top of the pad",
            "Lower until arms are nearly straight",
            "Don't let the bar drop fast at the bottom",
        ],
        "ez_curl": [
            "Hold the angled grips, elbows at your sides",
            "Curl without leaning back",
            "Lower slowly to full arm length",
        ],
        "preacher": [
            "Set the seat so armpits rest on top of the pad",
            "Curl up and squeeze at the top",
            "Lower under control, nearly to straight",
        ],
        "hammer_curl": [
            "Palms face each other the whole rep",
            "Elbows stay pinned at your sides",
            "No swinging, lower slowly",
        ],
        "rope_hammer": [
            "Hold the rope with palms facing each other",
            "Curl up with elbows at your sides",
            "Control the lowering, don't let the stack pull you",
        ],

        // Shoulders
        "db_ohp": [
            "Start with bells at shoulder height, palms forward",
            "Press straight up, bringing them slightly together",
            "Keep ribs down, don't arch your lower back",
        ],
        "bb_ohp": [
            "Grip just outside shoulders, bar on upper chest",
            "Move your head back, press up, then head through",
            "Squeeze glutes and abs so you don't lean back",
        ],
        "machine_ohp": [
            "Set the seat so handles start at shoulder height",
            "Back flat against the pad",
            "Press up without locking out hard, lower slowly",
        ],
        "smith_ohp": [
            "Set the bench so the bar lowers to your chin",
            "Back against the pad, feet flat",
            "Press straight up and lower under control",
        ],
        "lateral_raise": [
            "Slight bend in the elbows, slight forward lean",
            "Raise out to the sides to about shoulder height",
            "Don't shrug or swing, go light",
        ],
        "cable_lateral": [
            "Stand side-on with the cable set low",
            "Raise your arm out wide to shoulder height",
            "Lower slowly, keep the shoulder down",
        ],
        "machine_lateral": [
            "Line your shoulders up with the machine's pivot",
            "Lead with the elbows up to shoulder height",
            "Don't shrug, lower slowly",
        ],

        // Legs
        "leg_press": [
            "Feet about shoulder width in the middle of the platform",
            "Lower until knees are near 90°, back stays on the pad",
            "Don't lock your knees hard at the top",
        ],
        "hack_squat": [
            "Back and shoulders flat against the pad",
            "Feet shoulder width, knees track over your toes",
            "Go as deep as you can with your back on the pad",
        ],
        "bb_squat": [
            "Bar on upper back, feet about shoulder width",
            "Sit down and back, knees track over toes",
            "Keep your chest up and heels down the whole rep",
        ],
        "smith_squat": [
            "Feet slightly in front of the bar",
            "Sit down with your chest up and back flat",
            "Push through your whole foot to stand",
        ],
        "goblet_squat": [
            "Hold the bell at your chest, elbows down",
            "Sit between your knees, chest tall",
            "Keep heels down and knees pushing out",
        ],
        "leg_ext": [
            "Line your knee up with the machine's pivot",
            "Pad sits just above your ankles",
            "Straighten fully, squeeze, then lower slowly",
        ],
        "db_lunge": [
            "Take a long enough step that the front heel stays down",
            "Drop the back knee straight down toward the floor",
            "Keep your torso upright and push through the front foot",
        ],
        "leg_curl": [
            "Line your knee up with the machine's pivot",
            "Pad sits just above your heels",
            "Curl fully, then lower slowly, hips stay down",
        ],
        "db_rdl": [
            "Soft knees, push your hips straight back",
            "Bells slide down close to your legs",
            "Stop when your hamstrings are stretched, back flat",
        ],
        "bb_rdl": [
            "Soft knees, push your hips straight back",
            "Keep the bar touching or close to your legs",
            "Lower to a hamstring stretch, not to the floor",
        ],
        "bb_deadlift": [
            "Bar over mid-foot, shins close to the bar",
            "Brace, flat back, push the floor away",
            "Stand tall at the top without leaning back",
        ],
        "calf_raise_machine": [
            "Balls of your feet on the edge, heels free",
            "Lower for a full stretch, then rise all the way up",
            "Pause at the top, don't bounce at the bottom",
        ],
        "leg_press_calf": [
            "Balls of your feet on the bottom edge of the platform",
            "Keep your knees straight but not locked",
            "Full stretch at the bottom, full push at the top",
        ],
        "db_calf_raise": [
            "Stand on a step with heels hanging off",
            "Lower for a full stretch, then rise high",
            "Hold something for balance, go slow",
        ],

        // Abs
        "cable_crunch": [
            "Kneel facing the cable, rope beside your head",
            "Curl your ribs toward your hips",
            "Keep hips still, don't just pull with your arms",
        ],
        "ab_machine": [
            "Set the seat so the pads sit on your chest or shoulders",
            "Curl your chest toward your hips",
            "Exhale as you crunch, return slowly",
        ],
        "crunch": [
            "Knees bent, feet flat, hands lightly by your head",
            "Lift your shoulders by curling your ribs down",
            "Don't pull on your neck",
        ],
        "hanging_knee_raise": [
            "Hang with shoulders engaged, legs together",
            "Bring knees up and curl your hips toward your chest",
            "Lower slowly, no swinging",
        ],
        "lying_leg_raise": [
            "Lie flat with your lower back pressed into the floor",
            "Raise straight legs up to vertical",
            "Lower slowly without your back lifting off",
        ],
        "bicycle_crunch": [
            "Lower back pressed into the floor",
            "Bring opposite elbow toward knee as the other leg extends",
            "Go slow and twist from your ribs, not your neck",
        ],
    ]

    static func tips(for id: String) -> [String] { byID[id] ?? [] }
}
