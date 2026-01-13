import { GlobalExercise, ExerciseCategory } from '../types/workout';

export const globalExercises: GlobalExercise[] = [
    // --- CHEST (PECS) ---
    {
        id: 'barbell-bench-press',
        name: 'Barbell Bench Press',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Chest', 'Triceps', 'Front Delts'],
        equipment: ['Barbell', 'Bench'],
        defaultUnit: 'reps',
        difficulty: 'intermediate',
        description: 'The king of upper body exercises. Lie on a flat bench and press the weight up.'
    },
    {
        id: 'dumbbell-bench-press',
        name: 'Dumbbell Bench Press',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Chest', 'Triceps', 'Front Delts'],
        equipment: ['Dumbbell', 'Bench'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'incline-barbell-press',
        name: 'Incline Barbell Bench Press',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Upper Chest', 'Triceps', 'Front Delts'],
        equipment: ['Barbell', 'Bench'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'incline-dumbbell-press',
        name: 'Incline Dumbbell Press',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Upper Chest', 'Triceps', 'Front Delts'],
        equipment: ['Dumbbell', 'Bench'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'decline-barbell-press',
        name: 'Decline Barbell Bench Press',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Lower Chest', 'Triceps'],
        equipment: ['Barbell', 'Bench'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'decline-dumbbell-press',
        name: 'Decline Dumbbell Press',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Lower Chest', 'Triceps'],
        equipment: ['Dumbbell', 'Bench'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'dumbbell-fly',
        name: 'Dumbbell Fly',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Chest'],
        equipment: ['Dumbbell', 'Bench'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'incline-dumbbell-fly',
        name: 'Incline Dumbbell Fly',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Upper Chest'],
        equipment: ['Dumbbell', 'Bench'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'cable-crossover',
        name: 'Cable Crossover',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Chest'],
        equipment: ['Cable'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'high-to-low-cable-fly',
        name: 'High-to-Low Cable Fly',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Lower Chest'],
        equipment: ['Cable'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'low-to-high-cable-fly',
        name: 'Low-to-High Cable Fly',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Upper Chest'],
        equipment: ['Cable'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'machine-chest-press',
        name: 'Machine Chest Press',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Chest', 'Triceps'],
        equipment: ['Machine'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'pec-deck-machine',
        name: 'Pec Deck Machine',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Chest'],
        equipment: ['Machine'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'push-up',
        name: 'Push-Up',
        category: ExerciseCategory.Bodyweight,
        muscleGroups: ['Chest', 'Triceps', 'Core'],
        equipment: ['None'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'diamond-push-up',
        name: 'Diamond Push-Up',
        category: ExerciseCategory.Bodyweight,
        muscleGroups: ['Triceps', 'Chest'],
        equipment: ['None'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'decline-push-up',
        name: 'Decline Push-Up',
        category: ExerciseCategory.Bodyweight,
        muscleGroups: ['Upper Chest', 'Front Delts'],
        equipment: ['Bench'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'incline-push-up',
        name: 'Incline Push-Up',
        category: ExerciseCategory.Bodyweight,
        muscleGroups: ['Lower Chest'],
        equipment: ['Bench'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'weighted-push-up',
        name: 'Weighted Push-Up',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Chest', 'Triceps'],
        equipment: ['Plate'],
        defaultUnit: 'reps',
        difficulty: 'advanced'
    },
    {
        id: 'svend-press',
        name: 'Svend Press',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Chest'],
        equipment: ['Plate'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'landmine-press',
        name: 'Landmine Chest Press',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Upper Chest', 'Shoulders'],
        equipment: ['Barbell'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'floor-press',
        name: 'Floor Press',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Chest', 'Triceps'],
        equipment: ['Barbell'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'hammer-strength-wide-chest',
        name: 'Hammer Strength Wide Chest Press',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Chest'],
        equipment: ['Machine'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'chest-dip',
        name: 'Chest Dip',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Lower Chest', 'Triceps'],
        equipment: ['Other'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'single-arm-dumbbell-bench',
        name: 'Single-Arm Dumbbell Bench Press',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Chest', 'Core'],
        equipment: ['Dumbbell', 'Bench'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },

    // --- BACK ---
    {
        id: 'deadlift',
        name: 'Conventional Deadlift',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Back', 'Hamstrings', 'Glutes', 'Core'],
        equipment: ['Barbell'],
        defaultUnit: 'reps',
        difficulty: 'advanced'
    },
    {
        id: 'sumo-deadlift',
        name: 'Sumo Deadlift',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Hamstrings', 'Glutes', 'Adductors', 'Back'],
        equipment: ['Barbell'],
        defaultUnit: 'reps',
        difficulty: 'advanced'
    },
    {
        id: 'barbell-row',
        name: 'Bent Over Barbell Row',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Lats', 'Upper Back', 'Biceps'],
        equipment: ['Barbell'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'pendlay-row',
        name: 'Pendlay Row',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Mid Back', 'Lats'],
        equipment: ['Barbell'],
        defaultUnit: 'reps',
        difficulty: 'advanced'
    },
    {
        id: 'dumbbell-row',
        name: 'One-Arm Dumbbell Row',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Lats', 'Upper Back'],
        equipment: ['Dumbbell', 'Bench'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 't-bar-row',
        name: 'T-Bar Row',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Mid Back', 'Lats'],
        equipment: ['Barbell', 'Other'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'lat-pulldown-wide',
        name: 'Wide Grip Lat Pulldown',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Lats'],
        equipment: ['Cable'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'lat-pulldown-close',
        name: 'Close Grip Lat Pulldown',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Lats', 'Lower Traps'],
        equipment: ['Cable'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'pull-up',
        name: 'Pull-Up',
        category: ExerciseCategory.Bodyweight,
        muscleGroups: ['Lats', 'Biceps'],
        equipment: ['Other'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'chin-up',
        name: 'Chin-Up',
        category: ExerciseCategory.Bodyweight,
        muscleGroups: ['Biceps', 'Lats'],
        equipment: ['Other'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'inverted-row',
        name: 'Inverted Row',
        category: ExerciseCategory.Bodyweight,
        muscleGroups: ['Mid Back', 'Rear Delts'],
        equipment: ['Other'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'seated-cable-row',
        name: 'Seated Cable Row',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Mid Back', 'Lats'],
        equipment: ['Cable'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'straight-arm-pulldown',
        name: 'Straight Arm Cable Pulldown',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Lats'],
        equipment: ['Cable'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'single-arm-lat-pulldown',
        name: 'Single Arm Lat Pulldown',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Lats'],
        equipment: ['Cable'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'face-pull',
        name: 'Face Pull',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Rear Delts', 'Upper Back'],
        equipment: ['Cable'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'barbell-shrug',
        name: 'Barbell Shrug',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Traps'],
        equipment: ['Barbell'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'dumbbell-shrug',
        name: 'Dumbbell Shrug',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Traps'],
        equipment: ['Dumbbell'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'hyper-extension',
        name: 'Hyper-Extension',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Lower Back', 'Glutes'],
        equipment: ['Bench'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'good-morning',
        name: 'Good Morning',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Hamstrings', 'Lower Back'],
        equipment: ['Barbell'],
        defaultUnit: 'reps',
        difficulty: 'advanced'
    },
    {
        id: 'renegade-row',
        name: 'Renegade Row',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Back', 'Core', 'Shoulders'],
        equipment: ['Dumbbell'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'meadows-row',
        name: 'Meadows Row',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Mid Back', 'Lats'],
        equipment: ['Barbell'],
        defaultUnit: 'reps',
        difficulty: 'advanced'
    },
    {
        id: 'chest-supported-dumbbell-row',
        name: 'Chest Supported Dumbbell Row',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Upper Back'],
        equipment: ['Dumbbell', 'Bench'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'seal-row',
        name: 'Seal Row',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Mid Back'],
        equipment: ['Barbell', 'Bench'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'v-bar-pulldown',
        name: 'V-Bar Lat Pulldown',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Lats'],
        equipment: ['Cable'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'kettlebell-swing',
        name: 'Kettlebell Swing',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Hamstrings', 'Glutes', 'Back'],
        equipment: ['Kettlebell'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },

    // --- SHOULDERS ---
    {
        id: 'overhead-press',
        name: 'Standing Barbell Overhead Press',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Shoulders', 'Triceps', 'Core'],
        equipment: ['Barbell'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'seated-barbell-press',
        name: 'Seated Barbell Overhead Press',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Shoulders', 'Triceps'],
        equipment: ['Barbell', 'Bench'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'dumbbell-shoulder-press',
        name: 'Seated Dumbbell Shoulder Press',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Shoulders', 'Triceps'],
        equipment: ['Dumbbell', 'Bench'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'arnold-press',
        name: 'Arnold Press',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Shoulders', 'Triceps'],
        equipment: ['Dumbbell', 'Bench'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'dumbbell-lateral-raise',
        name: 'Dumbbell Lateral Raise',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Side Delts'],
        equipment: ['Dumbbell'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'cable-lateral-raise',
        name: 'Single-Arm Cable Lateral Raise',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Side Delts'],
        equipment: ['Cable'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'dumbbell-front-raise',
        name: 'Dumbbell Front Raise',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Front Delts'],
        equipment: ['Dumbbell'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'barbell-front-raise',
        name: 'Barbell Front Raise',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Front Delts'],
        equipment: ['Barbell'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'rear-delt-fly-dumbbell',
        name: 'Bent Over Dumbbell Rear Delt Fly',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Rear Delts'],
        equipment: ['Dumbbell'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'rear-delt-cable-fly',
        name: 'Reverse Cable Fly',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Rear Delts'],
        equipment: ['Cable'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'upright-row-barbell',
        name: 'Barbell Upright Row',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Shoulders', 'Traps'],
        equipment: ['Barbell'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'dumbbell-push-press',
        name: 'Dumbbell Push Press',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Shoulders', 'Triceps', 'Legs'],
        equipment: ['Dumbbell'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'handstand-push-up',
        name: 'Handstand Push-Up',
        category: ExerciseCategory.Bodyweight,
        muscleGroups: ['Shoulders', 'Triceps', 'Core'],
        equipment: ['None'],
        defaultUnit: 'reps',
        difficulty: 'advanced'
    },
    {
        id: 'landmine-press-shoulder',
        name: 'Landmine Shoulder Press',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Shoulders', 'Core'],
        equipment: ['Barbell'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'scaption',
        name: 'Dumbbell Scaption',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Shoulders', 'Rotator Cuff'],
        equipment: ['Dumbbell'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },

    // --- ARMS (BICEPS/TRICEPS/FOREARMS) ---
    {
        id: 'barbell-curl',
        name: 'Barbell Bicep Curl',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Biceps'],
        equipment: ['Barbell'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'dumbbell-curl',
        name: 'Dumbbell Bicep Curl',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Biceps'],
        equipment: ['Dumbbell'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'hammer-curl',
        name: 'Dumbbell Hammer Curl',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Biceps', 'Forearms'],
        equipment: ['Dumbbell'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'preacher-curl-ez',
        name: 'EZ-Bar Preacher Curl',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Biceps'],
        equipment: ['Barbell', 'Bench'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'concentration-curl',
        name: 'Dumbbell Concentration Curl',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Biceps'],
        equipment: ['Dumbbell', 'Bench'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'incline-dumbbell-curl',
        name: 'Incline Dumbbell Curl',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Biceps'],
        equipment: ['Dumbbell', 'Bench'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'cable-curl-rope',
        name: 'Cable Bicep Curl (Rope)',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Biceps'],
        equipment: ['Cable'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'spider-curl',
        name: 'Spider Curl',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Biceps'],
        equipment: ['Barbell', 'Bench'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'reverse-grip-curl',
        name: 'Reverse Grip Bicep Curl',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Forearms', 'Biceps'],
        equipment: ['Barbell'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'wrist-curl-barbell',
        name: 'Barbell Wrist Curl',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Forearms'],
        equipment: ['Barbell'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'skullcrusher-ez',
        name: 'EZ-Bar Skullcrusher',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Triceps'],
        equipment: ['Barbell', 'Bench'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'tricep-pushdown-rope',
        name: 'Tricep Rope Pushdown',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Triceps'],
        equipment: ['Cable'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'tricep-pushdown-bar',
        name: 'Tricep Straight Bar Pushdown',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Triceps'],
        equipment: ['Cable'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'overhead-tricep-extension-dumbbell',
        name: 'Overhead Dumbbell Tricep Extension',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Triceps'],
        equipment: ['Dumbbell'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'overhead-tricep-extension-cable',
        name: 'Overhead Cable Tricep Extension',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Triceps'],
        equipment: ['Cable'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'tricep-dip-bench',
        name: 'Bench Dip',
        category: ExerciseCategory.Bodyweight,
        muscleGroups: ['Triceps', 'Chest'],
        equipment: ['Bench'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'close-grip-bench-press',
        name: 'Close Grip Barbell Bench Press',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Triceps', 'Chest'],
        equipment: ['Barbell', 'Bench'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'tricep-kickback-dumbbell',
        name: 'Dumbbell Tricep Kickback',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Triceps'],
        equipment: ['Dumbbell'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'jm-press',
        name: 'JM Press',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Triceps'],
        equipment: ['Barbell'],
        defaultUnit: 'reps',
        difficulty: 'advanced'
    },
    {
        id: 'single-arm-cable-pushdown',
        name: 'Single Arm Cable Pushdown',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Triceps'],
        equipment: ['Cable'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'zottman-curl',
        name: 'Zottman Curl',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Biceps', 'Forearms'],
        equipment: ['Dumbbell'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'farmer-walk',
        name: 'Farmer\'s Walk',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Forearms', 'Core', 'Full Body'],
        equipment: ['Dumbbell'],
        defaultUnit: 's',
        difficulty: 'beginner'
    },

    // --- LEGS (QUADS/GLUTES/HAMS/CALVES) ---
    {
        id: 'barbell-back-squat',
        name: 'Barbell Back Squat',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Quads', 'Glutes', 'Core'],
        equipment: ['Barbell', 'Other'],
        defaultUnit: 'reps',
        difficulty: 'advanced'
    },
    {
        id: 'barbell-front-squat',
        name: 'Barbell Front Squat',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Quads', 'Upper Back', 'Core'],
        equipment: ['Barbell', 'Other'],
        defaultUnit: 'reps',
        difficulty: 'advanced'
    },
    {
        id: 'dumbbell-goblet-squat',
        name: 'Dumbbell Goblet Squat',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Quads', 'Glutes'],
        equipment: ['Dumbbell'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'leg-press',
        name: 'Leg Press',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Quads', 'Glutes'],
        equipment: ['Machine'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'hack-squat',
        name: 'Hack Squat Machine',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Quads', 'Glutes'],
        equipment: ['Machine'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'bulgarian-split-squat-dumbbell',
        name: 'Bulgarian Split Squat (Dumbbells)',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Quads', 'Glutes'],
        equipment: ['Dumbbell', 'Bench'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'walking-lunge-dumbbell',
        name: 'Dumbbell Walking Lunge',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Quads', 'Glutes', 'Hamstrings'],
        equipment: ['Dumbbell'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'romanian-deadlift-barbell',
        name: 'Barbell Romanian Deadlift (RDL)',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Hamstrings', 'Glutes', 'Lower Back'],
        equipment: ['Barbell'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'romanian-deadlift-dumbbell',
        name: 'Dumbbell Romanian Deadlift',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Hamstrings', 'Glutes'],
        equipment: ['Dumbbell'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'stiff-leg-deadlift',
        name: 'Stiff Leg Barbell Deadlift',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Hamstrings', 'Lower Back'],
        equipment: ['Barbell'],
        defaultUnit: 'reps',
        difficulty: 'advanced'
    },
    {
        id: 'leg-extension-machine',
        name: 'Leg Extension',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Quads'],
        equipment: ['Machine'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'lying-leg-curl-machine',
        name: 'Lying Leg Curl',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Hamstrings'],
        equipment: ['Machine'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'seated-leg-curl-machine',
        name: 'Seated Leg Curl',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Hamstrings'],
        equipment: ['Machine'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'standing-calf-raise-machine',
        name: 'Standing Calf Raise',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Calves'],
        equipment: ['Machine'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'seated-calf-raise-machine',
        name: 'Seated Calf Raise',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Calves'],
        equipment: ['Machine'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'donkey-calf-raise',
        name: 'Donkey Calf Raise',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Calves'],
        equipment: ['Machine'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'hip-thrust-barbell',
        name: 'Barbell Hip Thrust',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Glutes', 'Hamstrings'],
        equipment: ['Barbell', 'Bench'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'glute-bridge-bodyweight',
        name: 'Bodyweight Glute Bridge',
        category: ExerciseCategory.Bodyweight,
        muscleGroups: ['Glutes'],
        equipment: ['None'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'cable-glute-kickback',
        name: 'Cable Glute Kickback',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Glutes'],
        equipment: ['Cable'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'adductor-machine',
        name: 'Seated Adductor Machine',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Adductors'],
        equipment: ['Machine'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'abductor-machine',
        name: 'Seated Abductor Machine',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Abductors'],
        equipment: ['Machine'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'step-up-dumbbell',
        name: 'Dumbbell Step-Up',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Quads', 'Glutes'],
        equipment: ['Dumbbell', 'Bench'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'pistol-squat',
        name: 'Pistol Squat',
        category: ExerciseCategory.Bodyweight,
        muscleGroups: ['Quads', 'Glutes', 'Core'],
        equipment: ['None'],
        defaultUnit: 'reps',
        difficulty: 'advanced'
    },
    {
        id: 'nordic-hamstring-curl',
        name: 'Nordic Hamstring Curl',
        category: ExerciseCategory.Bodyweight,
        muscleGroups: ['Hamstrings'],
        equipment: ['None'],
        defaultUnit: 'reps',
        difficulty: 'advanced'
    },
    {
        id: 'sissy-squat',
        name: 'Sissy Squat',
        category: ExerciseCategory.Bodyweight,
        muscleGroups: ['Quads'],
        equipment: ['None'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'box-squat-barbell',
        name: 'Barbell Box Squat',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Glutes', 'Hamstrings', 'Quads'],
        equipment: ['Barbell', 'Bench'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'zercher-squat',
        name: 'Zercher Squat',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Quads', 'Core', 'Upper Back'],
        equipment: ['Barbell'],
        defaultUnit: 'reps',
        difficulty: 'advanced'
    },
    {
        id: 'side-lunge-dumbbell',
        name: 'Dumbbell Side Lunge',
        category: ExerciseCategory.Strength,
        muscleGroups: ['Glutes', 'Adductors', 'Quads'],
        equipment: ['Dumbbell'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },

    // --- CORE (ABS/OBLIQUES) ---
    {
        id: 'hanging-leg-raise',
        name: 'Hanging Leg Raise',
        category: ExerciseCategory.Core,
        muscleGroups: ['Abs', 'Hip Flexors'],
        equipment: ['Other'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'captain-chair-leg-raise',
        name: 'Captain\'s Chair Leg Raise',
        category: ExerciseCategory.Core,
        muscleGroups: ['Abs'],
        equipment: ['Other'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'ab-wheel-rollout',
        name: 'Ab Wheel Rollout',
        category: ExerciseCategory.Core,
        muscleGroups: ['Abs', 'Core'],
        equipment: ['Other'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'cable-crunch',
        name: 'Rope Cable Crunch',
        category: ExerciseCategory.Core,
        muscleGroups: ['Abs'],
        equipment: ['Cable'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'plank-bodyweight',
        name: 'Standard Plank',
        category: ExerciseCategory.Core,
        muscleGroups: ['Abs', 'Core'],
        equipment: ['None'],
        defaultUnit: 's',
        difficulty: 'beginner'
    },
    {
        id: 'side-plank-bodyweight',
        name: 'Side Plank',
        category: ExerciseCategory.Core,
        muscleGroups: ['Obliques'],
        equipment: ['None'],
        defaultUnit: 's',
        difficulty: 'beginner'
    },
    {
        id: 'russian-twist-dumbbell',
        name: 'Dumbbell Russian Twist',
        category: ExerciseCategory.Core,
        muscleGroups: ['Obliques', 'Abs'],
        equipment: ['Dumbbell'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'weighted-sit-up',
        name: 'Weighted Sit-Up',
        category: ExerciseCategory.Core,
        muscleGroups: ['Abs'],
        equipment: ['Plate'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'decline-crunch-weighted',
        name: 'Decline Weighted Crunch',
        category: ExerciseCategory.Core,
        muscleGroups: ['Abs'],
        equipment: ['Plate', 'Bench'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'wood-chopper-cable',
        name: 'Cable Wood Chopper',
        category: ExerciseCategory.Core,
        muscleGroups: ['Obliques', 'Core'],
        equipment: ['Cable'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'pallof-press-cable',
        name: 'Cable Pallof Press',
        category: ExerciseCategory.Core,
        muscleGroups: ['Core', 'Obliques'],
        equipment: ['Cable'],
        defaultUnit: 's',
        difficulty: 'beginner'
    },
    {
        id: 'bicycle-crunch',
        name: 'Bicycle Crunch',
        category: ExerciseCategory.Core,
        muscleGroups: ['Abs', 'Obliques'],
        equipment: ['None'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'v-up',
        name: 'V-Up',
        category: ExerciseCategory.Core,
        muscleGroups: ['Abs'],
        equipment: ['None'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'hollow-body-hold',
        name: 'Hollow Body Hold',
        category: ExerciseCategory.Core,
        muscleGroups: ['Abs', 'Core'],
        equipment: ['None'],
        defaultUnit: 's',
        difficulty: 'intermediate'
    },
    {
        id: 'l-sit',
        name: 'L-Sit Hold',
        category: ExerciseCategory.Core,
        muscleGroups: ['Abs', 'Hip Flexors', 'Shoulders'],
        equipment: ['Other'],
        defaultUnit: 's',
        difficulty: 'advanced'
    },
    {
        id: 'dragon-flag',
        name: 'Dragon Flag',
        category: ExerciseCategory.Core,
        muscleGroups: ['Abs', 'Core'],
        equipment: ['Bench'],
        defaultUnit: 'reps',
        difficulty: 'advanced'
    },
    {
        id: 'reverse-crunch',
        name: 'Reverse Crunch',
        category: ExerciseCategory.Core,
        muscleGroups: ['Lower Abs'],
        equipment: ['None'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'mountain-climber',
        name: 'Mountain Climbers',
        category: ExerciseCategory.Core,
        muscleGroups: ['Abs', 'Core', 'Cardio'],
        equipment: ['None'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },

    // --- CARDIO (HIIT/LISS) ---
    {
        id: 'treadmill-run',
        name: 'Treadmill Run',
        category: ExerciseCategory.Cardio,
        muscleGroups: ['Legs', 'Cardiovascular'],
        equipment: ['Machine'],
        defaultUnit: 'min',
        difficulty: 'beginner'
    },
    {
        id: 'stationary-bike',
        name: 'Stationary Bike (LISS)',
        category: ExerciseCategory.Cardio,
        muscleGroups: ['Legs'],
        equipment: ['Machine'],
        defaultUnit: 'min',
        difficulty: 'beginner'
    },
    {
        id: 'elliptical-trainer',
        name: 'Elliptical Trainer',
        category: ExerciseCategory.Cardio,
        muscleGroups: ['Full Body'],
        equipment: ['Machine'],
        defaultUnit: 'min',
        difficulty: 'beginner'
    },
    {
        id: 'stair-master',
        name: 'StairMaster',
        category: ExerciseCategory.Cardio,
        muscleGroups: ['Legs', 'Glutes'],
        equipment: ['Machine'],
        defaultUnit: 'min',
        difficulty: 'intermediate'
    },
    {
        id: 'rowing-machine',
        name: 'Indoor Rowing',
        category: ExerciseCategory.Cardio,
        muscleGroups: ['Back', 'Legs', 'Arms'],
        equipment: ['Machine'],
        defaultUnit: 'min',
        difficulty: 'intermediate'
    },
    {
        id: 'jump-rope',
        name: 'Jump Rope',
        category: ExerciseCategory.Cardio,
        muscleGroups: ['Calves', 'Shoulders'],
        equipment: ['Other'],
        defaultUnit: 'min',
        difficulty: 'beginner'
    },
    {
        id: 'battle-ropes',
        name: 'Battle Ropes',
        category: ExerciseCategory.Cardio,
        muscleGroups: ['Shoulders', 'Arms', 'Core'],
        equipment: ['Other'],
        defaultUnit: 's',
        difficulty: 'intermediate'
    },
    {
        id: 'shadow-boxing',
        name: 'Shadow Boxing',
        category: ExerciseCategory.Cardio,
        muscleGroups: ['Shoulders', 'Arms', 'Full Body'],
        equipment: ['None'],
        defaultUnit: 'min',
        difficulty: 'beginner'
    },
    {
        id: 'burpees',
        name: 'Burpees',
        category: ExerciseCategory.Cardio,
        muscleGroups: ['Full Body'],
        equipment: ['None'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'assault-bike-sprint',
        name: 'Assault Bike Sprints',
        category: ExerciseCategory.Cardio,
        muscleGroups: ['Full Body'],
        equipment: ['Machine'],
        defaultUnit: 's',
        difficulty: 'advanced'
    },

    // --- PLYOMETRICS ---
    {
        id: 'box-jump',
        name: 'Box Jump',
        category: ExerciseCategory.Plyometrics,
        muscleGroups: ['Legs'],
        equipment: ['Other'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'depth-jump',
        name: 'Depth Jump',
        category: ExerciseCategory.Plyometrics,
        muscleGroups: ['Legs'],
        equipment: ['Other'],
        defaultUnit: 'reps',
        difficulty: 'advanced'
    },
    {
        id: 'broad-jump',
        name: 'Broad Jump',
        category: ExerciseCategory.Plyometrics,
        muscleGroups: ['Legs'],
        equipment: ['None'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'tuck-jump',
        name: 'Tuck Jump',
        category: ExerciseCategory.Plyometrics,
        muscleGroups: ['Legs', 'Core'],
        equipment: ['None'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'skater-jump',
        name: 'Skater Jumps',
        category: ExerciseCategory.Plyometrics,
        muscleGroups: ['Legs', 'Glutes'],
        equipment: ['None'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'clap-push-up',
        name: 'Clap Push-Up',
        category: ExerciseCategory.Plyometrics,
        muscleGroups: ['Chest', 'Triceps'],
        equipment: ['None'],
        defaultUnit: 'reps',
        difficulty: 'advanced'
    },
    {
        id: 'jump-squat',
        name: 'Jump Squats',
        category: ExerciseCategory.Plyometrics,
        muscleGroups: ['Legs'],
        equipment: ['None'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },

    // --- MOBILITY & WARMUP ---
    {
        id: 'world-greatest-stretch',
        name: 'World\'s Greatest Stretch',
        category: ExerciseCategory.Mobility,
        muscleGroups: ['Full Body', 'Hips', 'Shoulders'],
        equipment: ['None'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'cat-cow',
        name: 'Cat-Cow',
        category: ExerciseCategory.Mobility,
        muscleGroups: ['Spine'],
        equipment: ['None'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'scapular-pull-up',
        name: 'Scapular Pull-Ups',
        category: ExerciseCategory.Warmup,
        muscleGroups: ['Back', 'Shoulders'],
        equipment: ['Other'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'band-pull-apart',
        name: 'Band Pull-Apart',
        category: ExerciseCategory.Warmup,
        muscleGroups: ['Rear Delts', 'Upper Back'],
        equipment: ['Band'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'shoulder-dislocate-band',
        name: 'Shoulder Pass-Through (Band)',
        category: ExerciseCategory.Mobility,
        muscleGroups: ['Shoulders'],
        equipment: ['Band'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'pigeon-stretch',
        name: 'Pigeon Stretch',
        category: ExerciseCategory.Mobility,
        muscleGroups: ['Glutes', 'Hips'],
        equipment: ['None'],
        defaultUnit: 's',
        difficulty: 'beginner'
    },
    {
        id: 'foam-roll-quads',
        name: 'Foam Roll - Quads',
        category: ExerciseCategory.Mobility,
        muscleGroups: ['Quads'],
        equipment: ['Other'],
        defaultUnit: 'min',
        difficulty: 'beginner'
    },
    {
        id: 'foam-roll-lats',
        name: 'Foam Roll - Lats',
        category: ExerciseCategory.Mobility,
        muscleGroups: ['Lats'],
        equipment: ['Other'],
        defaultUnit: 'min',
        difficulty: 'beginner'
    },
    {
        id: 'couch-stretch',
        name: 'Couch Stretch',
        category: ExerciseCategory.Mobility,
        muscleGroups: ['Quads', 'Hip Flexors'],
        equipment: ['Other'],
        defaultUnit: 's',
        difficulty: 'beginner'
    },
    {
        id: 'downward-dog',
        name: 'Downward Dog',
        category: ExerciseCategory.Mobility,
        muscleGroups: ['Shoulders', 'Hamstrings'],
        equipment: ['None'],
        defaultUnit: 's',
        difficulty: 'beginner'
    },
    {
        id: 'active-hanging',
        name: 'Active Bar Hang',
        category: ExerciseCategory.Warmup,
        muscleGroups: ['Shoulders', 'Grip'],
        equipment: ['Other'],
        defaultUnit: 's',
        difficulty: 'intermediate'
    },
    {
        id: '90-90-hip-switch',
        name: '90/90 Hip Switches',
        category: ExerciseCategory.Mobility,
        muscleGroups: ['Hips'],
        equipment: ['None'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'cobra-stretch',
        name: 'Cobra Stretch',
        category: ExerciseCategory.Mobility,
        muscleGroups: ['Abs', 'Spine'],
        equipment: ['None'],
        defaultUnit: 's',
        difficulty: 'beginner'
    },
    {
        id: 'thoracic-bridge',
        name: 'Thoracic Bridge',
        category: ExerciseCategory.Mobility,
        muscleGroups: ['Spine', 'Shoulders', 'Hips'],
        equipment: ['None'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },

    // --- MACHINE & SPECIALTY VARIATIONS ---
    { id: 'chest-press-hammer-strength', name: 'Hammer Strength Chest Press', category: ExerciseCategory.Strength, muscleGroups: ['Chest', 'Triceps'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'incline-chest-press-machine', name: 'Seated Incline Machine Press', category: ExerciseCategory.Strength, muscleGroups: ['Upper Chest', 'Triceps'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'chest-fly-machine', name: 'Machine Chest Fly', category: ExerciseCategory.Strength, muscleGroups: ['Chest'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'cable-chest-press', name: 'Standing Cable Chest Press', category: ExerciseCategory.Strength, muscleGroups: ['Chest', 'Core'], equipment: ['Cable'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'smith-machine-bench-press', name: 'Smith Machine Bench Press', category: ExerciseCategory.Strength, muscleGroups: ['Chest', 'Triceps'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'smith-machine-incline-press', name: 'Smith Machine Incline Press', category: ExerciseCategory.Strength, muscleGroups: ['Upper Chest', 'Triceps'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'low-row-machine', name: 'Seated Low Row Machine', category: ExerciseCategory.Strength, muscleGroups: ['Mid Back', 'Lats'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'high-row-machine', name: 'Seated High Row Machine', category: ExerciseCategory.Strength, muscleGroups: ['Upper Back', 'Lats'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'iso-lateral-row-hammer', name: 'Iso-Lateral Hammer Strength Row', category: ExerciseCategory.Strength, muscleGroups: ['Lats', 'Back'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'pullover-machine', name: 'Machine Pullover', category: ExerciseCategory.Strength, muscleGroups: ['Lats', 'Serratus'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'dumbbell-pullover', name: 'Dumbbell Pullover', category: ExerciseCategory.Strength, muscleGroups: ['Lats', 'Chest'], equipment: ['Dumbbell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'shoulder-press-machine', name: 'Machine Shoulder Press', category: ExerciseCategory.Strength, muscleGroups: ['Shoulders', 'Triceps'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'lateral-raise-machine', name: 'Machine Lateral Raise', category: ExerciseCategory.Strength, muscleGroups: ['Side Delts'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'reverse-fly-machine', name: 'Machine Reverse Fly (Rear Delt)', category: ExerciseCategory.Strength, muscleGroups: ['Rear Delts'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'bicep-curl-machine', name: 'Machine Bicep Curl', category: ExerciseCategory.Strength, muscleGroups: ['Biceps'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'tricep-extension-machine', name: 'Machine Tricep Extension', category: ExerciseCategory.Strength, muscleGroups: ['Triceps'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'dip-machine', name: 'Seated Dip Machine', category: ExerciseCategory.Strength, muscleGroups: ['Triceps', 'Chest'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'belt-squat', name: 'Belt Squat', category: ExerciseCategory.Strength, muscleGroups: ['Quads', 'Glutes'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'goblet-squat-kettlebell', name: 'Kettlebell Goblet Squat', category: ExerciseCategory.Strength, muscleGroups: ['Quads', 'Glutes'], equipment: ['Kettlebell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'split-squat-kettlebell', name: 'Kettlebell Split Squat', category: ExerciseCategory.Strength, muscleGroups: ['Quads', 'Glutes'], equipment: ['Kettlebell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'glute-drive-machine', name: 'Machine Glute Drive (Hip Thrust)', category: ExerciseCategory.Strength, muscleGroups: ['Glutes'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'single-leg-leg-press', name: 'Single-Arm Leg Press', category: ExerciseCategory.Strength, muscleGroups: ['Quads', 'Glutes'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'tibialis-raise', name: 'Tibialis Raise', category: ExerciseCategory.Strength, muscleGroups: ['Calves'], equipment: ['None'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'landmine-squat', name: 'Landmine Squat', category: ExerciseCategory.Strength, muscleGroups: ['Quads', 'Glutes'], equipment: ['Barbell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'landmine-row', name: 'Single-Arm Landmine Row', category: ExerciseCategory.Strength, muscleGroups: ['Lats', 'Upper Back'], equipment: ['Barbell'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'kettlebell-clean', name: 'Kettlebell Clean', category: ExerciseCategory.Strength, muscleGroups: ['Full Body', 'Shoulders'], equipment: ['Kettlebell'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'kettlebell-snatch', name: 'Kettlebell Snatch', category: ExerciseCategory.Strength, muscleGroups: ['Full Body', 'Shoulders'], equipment: ['Kettlebell'], defaultUnit: 'reps', difficulty: 'advanced' },
    { id: 'kettlebell-press', name: 'Kettlebell Overhead Press', category: ExerciseCategory.Strength, muscleGroups: ['Shoulders', 'Triceps'], equipment: ['Kettlebell'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'turkish-get-up', name: 'Turkish Get-Up', category: ExerciseCategory.Strength, muscleGroups: ['Full Body', 'Core', 'Shoulders'], equipment: ['Kettlebell'], defaultUnit: 'reps', difficulty: 'advanced' },
    { id: 'sandbag-carry', name: 'Sandbag Carry', category: ExerciseCategory.Strength, muscleGroups: ['Full Body', 'Core'], equipment: ['Other'], defaultUnit: 's', difficulty: 'intermediate' },
    { id: 'sled-push', name: 'Sled Push', category: ExerciseCategory.Strength, muscleGroups: ['Legs', 'Full Body'], equipment: ['Other'], defaultUnit: 's', difficulty: 'intermediate' },
    { id: 'sled-pull', name: 'Sled Pull', category: ExerciseCategory.Strength, muscleGroups: ['Legs', 'Back'], equipment: ['Other'], defaultUnit: 's', difficulty: 'intermediate' },
    { id: 'dead-hang', name: 'Dead Hang', category: ExerciseCategory.Warmup, muscleGroups: ['Grip', 'Shoulders'], equipment: ['Other'], defaultUnit: 's', difficulty: 'beginner' },
    { id: 'active-hang', name: 'Active Hang', category: ExerciseCategory.Warmup, muscleGroups: ['Back', 'Shoulders'], equipment: ['Other'], defaultUnit: 's', difficulty: 'intermediate' },
    { id: 'wall-slide', name: 'Wall Slides', category: ExerciseCategory.Mobility, muscleGroups: ['Shoulders', 'Upper Back'], equipment: ['None'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'scapular-push-up', name: 'Scapular Push-Ups', category: ExerciseCategory.Warmup, muscleGroups: ['Shoulders', 'Serratus'], equipment: ['None'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'face-pull-band', name: 'Band Face Pull', category: ExerciseCategory.Warmup, muscleGroups: ['Rear Delts'], equipment: ['Band'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'banded-lateral-raise', name: 'Resistance Band Lateral Raise', category: ExerciseCategory.Strength, muscleGroups: ['Side Delts'], equipment: ['Band'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'banded-bicep-curl', name: 'Resistance Band Bicep Curl', category: ExerciseCategory.Strength, muscleGroups: ['Biceps'], equipment: ['Band'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'banded-tricep-extension', name: 'Resistance Band Tricep Extension', category: ExerciseCategory.Strength, muscleGroups: ['Triceps'], equipment: ['Band'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'single-leg-rdl-dumbbell', name: 'Single-Leg Dumbbell RDL', category: ExerciseCategory.Strength, muscleGroups: ['Hamstrings', 'Glutes', 'Core'], equipment: ['Dumbbell'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'box-step-up-weighted', name: 'Weighted Box Step-Up', category: ExerciseCategory.Strength, muscleGroups: ['Quads', 'Glutes'], equipment: ['Dumbbell'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'copenhagen-plank', name: 'Copenhagen Plank', category: ExerciseCategory.Core, muscleGroups: ['Adductors', 'Core'], equipment: ['Bench'], defaultUnit: 's', difficulty: 'advanced' },
    { id: 'dead-bug', name: 'Dead Bug', category: ExerciseCategory.Core, muscleGroups: ['Abs', 'Core'], equipment: ['None'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'bird-dog', name: 'Bird-Dog', category: ExerciseCategory.Core, muscleGroups: ['Back', 'Core', 'Glutes'], equipment: ['None'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'superman-hold', name: 'Superman Hold', category: ExerciseCategory.Core, muscleGroups: ['Lower Back', 'Glutes'], equipment: ['None'], defaultUnit: 's', difficulty: 'beginner' },
    { id: 'l-sit-on-parallettes', name: 'L-Sit (Parallettes)', category: ExerciseCategory.Core, muscleGroups: ['Abs', 'Shoulders'], equipment: ['Other'], defaultUnit: 's', difficulty: 'advanced' },
    { id: 'planche-lean', name: 'Planche Lean', category: ExerciseCategory.Bodyweight, muscleGroups: ['Shoulders', 'Core'], equipment: ['None'], defaultUnit: 's', difficulty: 'advanced' },
    { id: 'front-lever-tuck', name: 'Tuck Front Lever', category: ExerciseCategory.Bodyweight, muscleGroups: ['Lats', 'Core'], equipment: ['Other'], defaultUnit: 's', difficulty: 'advanced' },
    { id: 'back-lever-tuck', name: 'Tuck Back Lever', category: ExerciseCategory.Bodyweight, muscleGroups: ['Back', 'Shoulders'], equipment: ['Other'], defaultUnit: 's', difficulty: 'advanced' },
    { id: 'muscle-up-rings', name: 'Ring Muscle-Up', category: ExerciseCategory.Bodyweight, muscleGroups: ['Full Body', 'Upper Body'], equipment: ['Other'], defaultUnit: 'reps', difficulty: 'advanced' },
    { id: 'muscle-up-bar', name: 'Bar Muscle-Up', category: ExerciseCategory.Bodyweight, muscleGroups: ['Full Body', 'Upper Body'], equipment: ['Other'], defaultUnit: 'reps', difficulty: 'advanced' },
    { id: 'box-squat-kettlebell', name: 'Kettlebell Box Squat', category: ExerciseCategory.Strength, muscleGroups: ['Glutes', 'Quads'], equipment: ['Kettlebell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'sumo-squat-dumbbell', name: 'Dumbbell Sumo Squat', category: ExerciseCategory.Strength, muscleGroups: ['Inner Thighs', 'Glutes'], equipment: ['Dumbbell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'curtsy-lunge', name: 'Curtsy Lunge', category: ExerciseCategory.Bodyweight, muscleGroups: ['Glutes', 'Quads'], equipment: ['None'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'side-lying-leg-lift', name: 'Side Lying Leg Lift', category: ExerciseCategory.Bodyweight, muscleGroups: ['Abductors'], equipment: ['None'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'donkey-kick', name: 'Donkey Kicks', category: ExerciseCategory.Bodyweight, muscleGroups: ['Glutes'], equipment: ['None'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'fire-hydrant', name: 'Fire Hydrants', category: ExerciseCategory.Bodyweight, muscleGroups: ['Abductors', 'Glutes'], equipment: ['None'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'glute-ham-developer-raise', name: 'GHD Sit-Up', category: ExerciseCategory.Core, muscleGroups: ['Abs', 'Hip Flexors'], equipment: ['Other'], defaultUnit: 'reps', difficulty: 'advanced' },
    { id: 'ghd-back-extension', name: 'GHD Back Extension', category: ExerciseCategory.Strength, muscleGroups: ['Lower Back', 'Hamstrings'], equipment: ['Other'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'kettlebell-halo', name: 'Kettlebell Halo', category: ExerciseCategory.Mobility, muscleGroups: ['Shoulders', 'Core'], equipment: ['Kettlebell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'overhead-squat-barbell', name: 'Barbell Overhead Squat', category: ExerciseCategory.Strength, muscleGroups: ['Full Body', 'Shoulders', 'Legs'], equipment: ['Barbell'], defaultUnit: 'reps', difficulty: 'advanced' },
    { id: 'overhead-squat-dumbbell', name: 'Dumbbell Overhead Squat', category: ExerciseCategory.Strength, muscleGroups: ['Shoulders', 'Core', 'Legs'], equipment: ['Dumbbell'], defaultUnit: 'reps', difficulty: 'advanced' },
    { id: 'wall-ball', name: 'Wall Ball Shot', category: ExerciseCategory.Plyometrics, muscleGroups: ['Full Body', 'Shoulders', 'Legs'], equipment: ['Other'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'medicine-ball-slam', name: 'Medicine Ball Slam', category: ExerciseCategory.Plyometrics, muscleGroups: ['Core', 'Shoulders', 'Full Body'], equipment: ['Other'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'box-jump-over', name: 'Box Jump Over', category: ExerciseCategory.Plyometrics, muscleGroups: ['Legs', 'Cardio'], equipment: ['Other'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'toes-to-bar', name: 'Toes to Bar', category: ExerciseCategory.Core, muscleGroups: ['Abs', 'Core', 'Grip'], equipment: ['Other'], defaultUnit: 'reps', difficulty: 'advanced' },
    { id: 'knees-to-elbows', name: 'Knees to Elbows', category: ExerciseCategory.Core, muscleGroups: ['Abs', 'Core'], equipment: ['Other'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'ab-mat-situp', name: 'AbMat Sit-Up', category: ExerciseCategory.Core, muscleGroups: ['Abs'], equipment: ['Other'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'flutter-kicks', name: 'Flutter Kicks', category: ExerciseCategory.Core, muscleGroups: ['Lower Abs'], equipment: ['None'], defaultUnit: 's', difficulty: 'beginner' },
    { id: 'leg-pendulum', name: 'Leg Pendulums', category: ExerciseCategory.Core, muscleGroups: ['Obliques', 'Abs'], equipment: ['None'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'windshield-wiper', name: 'Windshield Wipers', category: ExerciseCategory.Core, muscleGroups: ['Core', 'Obliques'], equipment: ['None'], defaultUnit: 'reps', difficulty: 'advanced' },
    { id: 'prone-cobra', name: 'Prone Cobra', category: ExerciseCategory.Mobility, muscleGroups: ['Posterior Chain', 'Spine'], equipment: ['None'], defaultUnit: 's', difficulty: 'beginner' },
    { id: 'child-pose', name: 'Child\'s Pose', category: ExerciseCategory.Mobility, muscleGroups: ['Back', 'Hips'], equipment: ['None'], defaultUnit: 's', difficulty: 'beginner' },
    { id: 'happy-baby-pose', name: 'Happy Baby Pose', category: ExerciseCategory.Mobility, muscleGroups: ['Hips'], equipment: ['None'], defaultUnit: 's', difficulty: 'beginner' },
    { id: 'seated-forward-fold', name: 'Seated Forward Fold', category: ExerciseCategory.Mobility, muscleGroups: ['Hamstrings', 'Lower Back'], equipment: ['None'], defaultUnit: 's', difficulty: 'beginner' },
    { id: 'calf-stretch-wall', name: 'Wall Calf Stretch', category: ExerciseCategory.Mobility, muscleGroups: ['Calves'], equipment: ['None'], defaultUnit: 's', difficulty: 'beginner' },
    { id: 'wrist-extension-stretch', name: 'Wrist Extension Stretch', category: ExerciseCategory.Mobility, muscleGroups: ['Forearms'], equipment: ['None'], defaultUnit: 's', difficulty: 'beginner' },
    { id: 'wrist-flexion-stretch', name: 'Wrist Flexion Stretch', category: ExerciseCategory.Mobility, muscleGroups: ['Forearms'], equipment: ['None'], defaultUnit: 's', difficulty: 'beginner' },
    { id: 'box-dip-weighted', name: 'Weighted Box Dip', category: ExerciseCategory.Strength, muscleGroups: ['Triceps', 'Chest'], equipment: ['Plate'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'ring-dip', name: 'Ring Dip', category: ExerciseCategory.Bodyweight, muscleGroups: ['Chest', 'Triceps', 'Shoulders'], equipment: ['Other'], defaultUnit: 'reps', difficulty: 'advanced' },
    { id: 'ring-push-up', name: 'Ring Push-Up', category: ExerciseCategory.Bodyweight, muscleGroups: ['Chest', 'Core'], equipment: ['Other'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'ring-row', name: 'Ring Row', category: ExerciseCategory.Bodyweight, muscleGroups: ['Back', 'Biceps'], equipment: ['Other'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'skipping', name: 'Skipping (High Knees)', category: ExerciseCategory.Cardio, muscleGroups: ['Full Body', 'Cardio'], equipment: ['None'], defaultUnit: 'min', difficulty: 'beginner' },
    { id: 'power-clean-barbell', name: 'Barbell Power Clean', category: ExerciseCategory.Strength, muscleGroups: ['Full Body', 'Traps', 'Legs'], equipment: ['Barbell'], defaultUnit: 'reps', difficulty: 'advanced' },
    { id: 'hang-clean-barbell', name: 'Barbell Hang Clean', category: ExerciseCategory.Strength, muscleGroups: ['Full Body', 'Traps'], equipment: ['Barbell'], defaultUnit: 'reps', difficulty: 'advanced' },
    { id: 'push-jerk-barbell', name: 'Barbell Push Jerk', category: ExerciseCategory.Strength, muscleGroups: ['Shoulders', 'Legs'], equipment: ['Barbell'], defaultUnit: 'reps', difficulty: 'advanced' },
    { id: 'split-jerk-barbell', name: 'Barbell Split Jerk', category: ExerciseCategory.Strength, muscleGroups: ['Shoulders', 'Legs'], equipment: ['Barbell'], defaultUnit: 'reps', difficulty: 'advanced' },
    { id: 'thruster-barbell', name: 'Barbell Thruster', category: ExerciseCategory.Strength, muscleGroups: ['Full Body', 'Legs', 'Shoulders'], equipment: ['Barbell'], defaultUnit: 'reps', difficulty: 'advanced' },
    { id: 'thruster-dumbbell', name: 'Dumbbell Thruster', category: ExerciseCategory.Strength, muscleGroups: ['Full Body', 'Legs', 'Shoulders'], equipment: ['Dumbbell'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'bear-crawl', name: 'Bear Crawl', category: ExerciseCategory.Cardio, muscleGroups: ['Full Body', 'Core'], equipment: ['None'], defaultUnit: 's', difficulty: 'intermediate' },
    { id: 'crab-walk', name: 'Crab Walk', category: ExerciseCategory.Cardio, muscleGroups: ['Shoulders', 'Triceps', 'Core'], equipment: ['None'], defaultUnit: 's', difficulty: 'beginner' },
    { id: 'mountain-climber-cross', name: 'Cross-Body Mountain Climbers', category: ExerciseCategory.Core, muscleGroups: ['Obliques', 'Core'], equipment: ['None'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'plank-jack', name: 'Plank Jacks', category: ExerciseCategory.Cardio, muscleGroups: ['Core', 'Cardio'], equipment: ['None'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'side-to-side-jump', name: 'Side-to-Side Jumps', category: ExerciseCategory.Plyometrics, muscleGroups: ['Legs', 'Cardio'], equipment: ['None'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'jumping-jack', name: 'Jumping Jacks', category: ExerciseCategory.Cardio, muscleGroups: ['Full Body'], equipment: ['None'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'high-knee-run', name: 'High Knees', category: ExerciseCategory.Cardio, muscleGroups: ['Full Body', 'Cardio'], equipment: ['None'], defaultUnit: 's', difficulty: 'beginner' },
    { id: 'butt-kick-run', name: 'Butt Kicks', category: ExerciseCategory.Cardio, muscleGroups: ['Hamstrings', 'Cardio'], equipment: ['None'], defaultUnit: 's', difficulty: 'beginner' },
    { id: 'weighted-vest-walk', name: 'Weighted Vest Walk', category: ExerciseCategory.Cardio, muscleGroups: ['Full Body'], equipment: ['Other'], defaultUnit: 'min', difficulty: 'beginner' },
    { id: 'farmer-carry-heavy', name: 'Heavy Farmer\'s Carry', category: ExerciseCategory.Strength, muscleGroups: ['Grip', 'Core', 'Full Body'], equipment: ['Dumbbell'], defaultUnit: 's', difficulty: 'intermediate' },
    { id: 'suitcase-carry', name: 'Suitcase Carry', category: ExerciseCategory.Core, muscleGroups: ['Obliques', 'Core', 'Grip'], equipment: ['Dumbbell'], defaultUnit: 's', difficulty: 'intermediate' },
    { id: 'waiter-carry', name: 'Waiter\'s Carry', category: ExerciseCategory.Core, muscleGroups: ['Shoulders', 'Core'], equipment: ['Kettlebell'], defaultUnit: 's', difficulty: 'intermediate' },
    { id: 'single-arm-dumbbell-snatch', name: 'Single-Arm Dumbbell Snatch', category: ExerciseCategory.Strength, muscleGroups: ['Full Body', 'Shoulders'], equipment: ['Dumbbell'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'banded-good-morning', name: 'Banded Good Morning', category: ExerciseCategory.Warmup, muscleGroups: ['Hamstrings', 'Lower Back'], equipment: ['Band'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'banded-clamshell', name: 'Banded Clamshells', category: ExerciseCategory.Warmup, muscleGroups: ['Glutes', 'Abductors'], equipment: ['Band'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'banded-glute-bridge', name: 'Banded Glute Bridge', category: ExerciseCategory.Warmup, muscleGroups: ['Glutes'], equipment: ['Band'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'monster-walk-band', name: 'Band Monster Walk', category: ExerciseCategory.Warmup, muscleGroups: ['Glutes', 'Abductors'], equipment: ['Band'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'lateral-walk-band', name: 'Band Lateral Walk', category: ExerciseCategory.Warmup, muscleGroups: ['Glutes', 'Abductors'], equipment: ['Band'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'tricep-overhead-band', name: 'Band Overhead Tricep Extension', category: ExerciseCategory.Strength, muscleGroups: ['Triceps'], equipment: ['Band'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'bicep-curl-band', name: 'Band Bicep Curl', category: ExerciseCategory.Strength, muscleGroups: ['Biceps'], equipment: ['Band'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'chest-press-band', name: 'Band Chest Press', category: ExerciseCategory.Strength, muscleGroups: ['Chest'], equipment: ['Band'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'row-banded', name: 'Banded Seated Row', category: ExerciseCategory.Strength, muscleGroups: ['Back'], equipment: ['Band'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'pull-apart-band', name: 'Band Pull-Aparts', category: ExerciseCategory.Warmup, muscleGroups: ['Rear Delts', 'Back'], equipment: ['Band'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'single-leg-glute-bridge', name: 'Single-Leg Glute Bridge', category: ExerciseCategory.Bodyweight, muscleGroups: ['Glutes'], equipment: ['None'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'side-lying-hip-abduction', name: 'Side-Lying Hip Abduction', category: ExerciseCategory.Bodyweight, muscleGroups: ['Abductors'], equipment: ['None'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'bird-dog-crunch', name: 'Bird-Dog Crunch', category: ExerciseCategory.Core, muscleGroups: ['Abs', 'Core'], equipment: ['None'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'hollow-body-rock', name: 'Hollow Body Rocks', category: ExerciseCategory.Core, muscleGroups: ['Core', 'Abs'], equipment: ['None'], defaultUnit: 'reps', difficulty: 'advanced' },
    { id: 'side-crunch', name: 'Side Crunch', category: ExerciseCategory.Core, muscleGroups: ['Obliques'], equipment: ['None'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'seated-knee-tuck', name: 'Seated Knee Tuck', category: ExerciseCategory.Core, muscleGroups: ['Abs'], equipment: ['Bench'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'bench-leg-raise', name: 'Bench Leg Raise', category: ExerciseCategory.Core, muscleGroups: ['Lower Abs'], equipment: ['Bench'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'weighted-plank', name: 'Weighted Plank', category: ExerciseCategory.Core, muscleGroups: ['Core', 'Abs'], equipment: ['Plate'], defaultUnit: 's', difficulty: 'intermediate' },
    { id: 'plank-to-pushup', name: 'Plank to Push-Up', category: ExerciseCategory.Core, muscleGroups: ['Full Body', 'Core', 'Chest'], equipment: ['None'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'spiderman-pushup', name: 'Spiderman Push-Up', category: ExerciseCategory.Bodyweight, muscleGroups: ['Chest', 'Obliques', 'Core'], equipment: ['None'], defaultUnit: 'reps', difficulty: 'advanced' },
    { id: 'archer-pushup', name: 'Archer Push-Up', category: ExerciseCategory.Bodyweight, muscleGroups: ['Chest', 'Shoulders'], equipment: ['None'], defaultUnit: 'reps', difficulty: 'advanced' },
    { id: 'typewriter-pushup', name: 'Typewriter Push-Up', category: ExerciseCategory.Bodyweight, muscleGroups: ['Chest', 'Shoulders'], equipment: ['None'], defaultUnit: 'reps', difficulty: 'advanced' },
    { id: 'explosive-pullup', name: 'Explosive Pull-Up', category: ExerciseCategory.Plyometrics, muscleGroups: ['Back', 'Biceps'], equipment: ['Other'], defaultUnit: 'reps', difficulty: 'advanced' },
    { id: 'weighted-pullup', name: 'Weighted Pull-Up', category: ExerciseCategory.Strength, muscleGroups: ['Back', 'Biceps'], equipment: ['Plate'], defaultUnit: 'reps', difficulty: 'advanced' },
    { id: 'weighted-dip', name: 'Weighted Dip', category: ExerciseCategory.Strength, muscleGroups: ['Chest', 'Triceps'], equipment: ['Plate'], defaultUnit: 'reps', difficulty: 'advanced' },
    { id: 'l-sit-pullup', name: 'L-Sit Pull-Up', category: ExerciseCategory.Bodyweight, muscleGroups: ['Back', 'Abs', 'Grip'], equipment: ['Other'], defaultUnit: 'reps', difficulty: 'advanced' },
    { id: 'wide-grip-pullup', name: 'Wide Grip Pull-Up', category: ExerciseCategory.Bodyweight, muscleGroups: ['Lats'], equipment: ['Other'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'close-grip-pullup', name: 'Close Grip Pull-Up', category: ExerciseCategory.Bodyweight, muscleGroups: ['Lats', 'Biceps'], equipment: ['Other'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'neutral-grip-pullup', name: 'Neutral Grip Pull-Up', category: ExerciseCategory.Bodyweight, muscleGroups: ['Back', 'Biceps'], equipment: ['Other'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'one-arm-pullup-progression', name: 'One-Arm Pull-Up Progression', category: ExerciseCategory.Bodyweight, muscleGroups: ['Back', 'Biceps', 'Grip'], equipment: ['Other'], defaultUnit: 'reps', difficulty: 'advanced' },
    { id: 'muscle-up-low-rings', name: 'Low Ring Muscle-Up (Transition)', category: ExerciseCategory.Bodyweight, muscleGroups: ['Upper Body'], equipment: ['Other'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'back-extension-machine', name: 'Machine Back Extension', category: ExerciseCategory.Strength, muscleGroups: ['Lower Back'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'torso-rotation-machine', name: 'Torso Rotation Machine', category: ExerciseCategory.Core, muscleGroups: ['Obliques'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'abdominal-crunch-machine', name: 'Machine Abdominal Crunch', category: ExerciseCategory.Core, muscleGroups: ['Abs'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'glute-kickback-machine', name: 'Machine Glute Kickback', category: ExerciseCategory.Strength, muscleGroups: ['Glutes'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'leg-curl-standing', name: 'Standing Machine Leg Curl', category: ExerciseCategory.Strength, muscleGroups: ['Hamstrings'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'chest-press-iso-lateral', name: 'Iso-Lateral Chest Press Machine', category: ExerciseCategory.Strength, muscleGroups: ['Chest', 'Triceps'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'shoulder-press-iso-lateral', name: 'Iso-Lateral Shoulder Press Machine', category: ExerciseCategory.Strength, muscleGroups: ['Shoulders', 'Triceps'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'lat-pulldown-iso-lateral', name: 'Iso-Lateral Lat Pulldown Machine', category: ExerciseCategory.Strength, muscleGroups: ['Lats', 'Biceps'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'low-row-iso-lateral', name: 'Iso-Lateral Low Row Machine', category: ExerciseCategory.Strength, muscleGroups: ['Back', 'Lats'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'unilateral-leg-extension', name: 'Unilateral Leg Extension', category: ExerciseCategory.Strength, muscleGroups: ['Quads'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'unilateral-leg-curl', name: 'Unilateral Leg Curl', category: ExerciseCategory.Strength, muscleGroups: ['Hamstrings'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'unilateral-leg-press', name: 'Unilateral Leg Press', category: ExerciseCategory.Strength, muscleGroups: ['Quads', 'Glutes'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'unilateral-calf-raise', name: 'Unilateral Calf Raise', category: ExerciseCategory.Strength, muscleGroups: ['Calves'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'dumbbell-pullover-chest', name: 'Dumbbell Chest Pullover', category: ExerciseCategory.Strength, muscleGroups: ['Chest', 'Lats'], equipment: ['Dumbbell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'barbell-pullover', name: 'Barbell Pullover', category: ExerciseCategory.Strength, muscleGroups: ['Lats', 'Chest'], equipment: ['Barbell'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'ez-bar-pullover', name: 'EZ-Bar Pullover', category: ExerciseCategory.Strength, muscleGroups: ['Lats', 'Triceps'], equipment: ['Barbell'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'dumbbell-squeeze-press', name: 'Dumbbell Squeeze Press', category: ExerciseCategory.Strength, muscleGroups: ['Inner Chest'], equipment: ['Dumbbell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'kettlebell-floor-press', name: 'Kettlebell Floor Press', category: ExerciseCategory.Strength, muscleGroups: ['Chest', 'Triceps'], equipment: ['Kettlebell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'kettlebell-bench-press', name: 'Kettlebell Bench Press', category: ExerciseCategory.Strength, muscleGroups: ['Chest', 'Triceps'], equipment: ['Kettlebell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'single-arm-dumbbell-fly', name: 'Single-Arm Dumbbell Fly', category: ExerciseCategory.Strength, muscleGroups: ['Chest', 'Core'], equipment: ['Dumbbell'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'single-arm-cable-chest-press', name: 'Single-Arm Cable Chest Press', category: ExerciseCategory.Strength, muscleGroups: ['Chest', 'Core'], equipment: ['Cable'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'svend-press-dumbbell', name: 'Dumbbell Svend Press', category: ExerciseCategory.Strength, muscleGroups: ['Inner Chest'], equipment: ['Dumbbell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'pec-deck-reverse-fly', name: 'Pec Deck Reverse Fly', category: ExerciseCategory.Strength, muscleGroups: ['Rear Delts', 'Upper Back'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'face-pull-with-external-rotation', name: 'Face Pull with External Rotation', category: ExerciseCategory.Strength, muscleGroups: ['Rear Delts', 'Rotator Cuff'], equipment: ['Cable'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'y-raise-dumbbell', name: 'Dumbbell Y-Raise', category: ExerciseCategory.Strength, muscleGroups: ['Lower Traps', 'Shoulders'], equipment: ['Dumbbell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 't-raise-dumbbell', name: 'Dumbbell T-Raise', category: ExerciseCategory.Strength, muscleGroups: ['Rear Delts', 'Upper Back'], equipment: ['Dumbbell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'w-raise-dumbbell', name: 'Dumbbell W-Raise', category: ExerciseCategory.Strength, muscleGroups: ['Rear Delts', 'Traps'], equipment: ['Dumbbell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'scaption-dumbbell', name: 'Dumbbell Scaption Raise', category: ExerciseCategory.Warmup, muscleGroups: ['Shoulders', 'Rotator Cuff'], equipment: ['Dumbbell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'cuff-external-rotation-cable', name: 'Cable External Rotation', category: ExerciseCategory.Mobility, muscleGroups: ['Rotator Cuff'], equipment: ['Cable'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'cuff-internal-rotation-cable', name: 'Cable Internal Rotation', category: ExerciseCategory.Mobility, muscleGroups: ['Rotator Cuff'], equipment: ['Cable'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'cuff-external-rotation-dumbbell', name: 'Dumbbell External Rotation', category: ExerciseCategory.Mobility, muscleGroups: ['Rotator Cuff'], equipment: ['Dumbbell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'single-arm-face-pull', name: 'Single-Arm Cable Face Pull', category: ExerciseCategory.Strength, muscleGroups: ['Rear Delts'], equipment: ['Cable'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'prone-dumbbell-row-rear-delt', name: 'Prone Rear Delt Row (Dumbbells)', category: ExerciseCategory.Strength, muscleGroups: ['Rear Delts', 'Upper Back'], equipment: ['Dumbbell', 'Bench'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'prone-barbell-row-bench', name: 'Prone Barbell Row (Bench)', category: ExerciseCategory.Strength, muscleGroups: ['Upper Back', 'Lats'], equipment: ['Barbell', 'Bench'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'kroc-row', name: 'Kroc Row (Heavy DB Row)', category: ExerciseCategory.Strength, muscleGroups: ['Lats', 'Back', 'Grip'], equipment: ['Dumbbell'], defaultUnit: 'reps', difficulty: 'advanced' },
    { id: 'single-arm-barbell-row', name: 'Single-Arm Barbell Row', category: ExerciseCategory.Strength, muscleGroups: ['Lats', 'Back'], equipment: ['Barbell'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'gorilla-row-kettlebell', name: 'Kettlebell Gorilla Row', category: ExerciseCategory.Strength, muscleGroups: ['Back', 'Core'], equipment: ['Kettlebell'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'alternating-dumbbell-row', name: 'Alternating Dumbbell Row', category: ExerciseCategory.Strength, muscleGroups: ['Back', 'Core'], equipment: ['Dumbbell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'bent-over-fly-dumbbell', name: 'Bent Over Dumbbell Fly', category: ExerciseCategory.Strength, muscleGroups: ['Rear Delts'], equipment: ['Dumbbell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'chest-supported-barbell-row', name: 'Chest Supported Barbell Row', category: ExerciseCategory.Strength, muscleGroups: ['Upper Back'], equipment: ['Barbell', 'Bench'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'v-bar-seated-row', name: 'V-Bar Seated Cable Row', category: ExerciseCategory.Strength, muscleGroups: ['Mid Back', 'Lats'], equipment: ['Cable'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'wide-grip-seated-row', name: 'Wide Grip Seated Cable Row', category: ExerciseCategory.Strength, muscleGroups: ['Upper Back'], equipment: ['Cable'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'close-grip-seated-row', name: 'Close Grip Seated Cable Row', category: ExerciseCategory.Strength, muscleGroups: ['Lats'], equipment: ['Cable'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'single-arm-seated-cable-row', name: 'Single-Arm Seated Cable Row', category: ExerciseCategory.Strength, muscleGroups: ['Lats', 'Core'], equipment: ['Cable'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'seated-row-machine-iso', name: 'Iso-Lateral Seated Row Machine', category: ExerciseCategory.Strength, muscleGroups: ['Back'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'rack-pull-barbell', name: 'Barbell Rack Pull', category: ExerciseCategory.Strength, muscleGroups: ['Upper Back', 'Lower Back', 'Glutes'], equipment: ['Barbell'], defaultUnit: 'reps', difficulty: 'advanced' },
    { id: 'block-pull-barbell', name: 'Barbell Block Pull', category: ExerciseCategory.Strength, muscleGroups: ['Back', 'Legs'], equipment: ['Barbell'], defaultUnit: 'reps', difficulty: 'advanced' },
    { id: 'deficit-deadlift-barbell', name: 'Barbell Deficit Deadlift', category: ExerciseCategory.Strength, muscleGroups: ['Back', 'Hamstrings', 'Glutes'], equipment: ['Barbell'], defaultUnit: 'reps', difficulty: 'advanced' },
    { id: 'trap-bar-deadlift', name: 'Trap Bar Deadlift', category: ExerciseCategory.Strength, muscleGroups: ['Full Body', 'Legs', 'Back'], equipment: ['Barbell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'stiff-leg-deadlift-dumbbell', name: 'Stiff Leg Dumbbell Deadlift', category: ExerciseCategory.Strength, muscleGroups: ['Hamstrings', 'Lower Back'], equipment: ['Dumbbell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'romanian-deadlift-kettlebell', name: 'Kettlebell Romanian Deadlift', category: ExerciseCategory.Strength, muscleGroups: ['Hamstrings', 'Glutes'], equipment: ['Kettlebell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'good-morning-seated', name: 'Seated Good Morning', category: ExerciseCategory.Strength, muscleGroups: ['Lower Back', 'Hamstrings'], equipment: ['Barbell', 'Bench'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'good-morning-dumbbell', name: 'Dumbbell Good Morning', category: ExerciseCategory.Strength, muscleGroups: ['Lower Back'], equipment: ['Dumbbell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'hyper-extension-weighted', name: 'Weighted Hyper-Extension', category: ExerciseCategory.Strength, muscleGroups: ['Lower Back', 'Glutes'], equipment: ['Plate'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'reverse-hyper-machine', name: 'Reverse Hyper-Extension', category: ExerciseCategory.Strength, muscleGroups: ['Lower Back', 'Glutes', 'Hamstrings'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'overhead-squat-kettlebell', name: 'Kettlebell Overhead Squat', category: ExerciseCategory.Strength, muscleGroups: ['Shoulders', 'Legs', 'Core'], equipment: ['Kettlebell'], defaultUnit: 'reps', difficulty: 'advanced' },
    { id: 'suitcase-deadlift-dumbbell', name: 'Suitcase Dumbbell Deadlift', category: ExerciseCategory.Core, muscleGroups: ['Core', 'Legs'], equipment: ['Dumbbell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'suitcase-deadlift-kettlebell', name: 'Suitcase Kettlebell Deadlift', category: ExerciseCategory.Core, muscleGroups: ['Core', 'Legs'], equipment: ['Kettlebell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'single-arm-kettlebell-swing', name: 'Single-Arm Kettlebell Swing', category: ExerciseCategory.Strength, muscleGroups: ['Hamstrings', 'Glutes', 'Core'], equipment: ['Kettlebell'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'alternating-kettlebell-swing', name: 'Alternating Kettlebell Swing', category: ExerciseCategory.Strength, muscleGroups: ['Hamstrings', 'Glutes'], equipment: ['Kettlebell'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'box-squat-dumbbell', name: 'Dumbbell Box Squat', category: ExerciseCategory.Strength, muscleGroups: ['Glutes', 'Quads'], equipment: ['Dumbbell', 'Bench'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'pause-squat-barbell', name: 'Barbell Pause Squat', category: ExerciseCategory.Strength, muscleGroups: ['Legs', 'Core'], equipment: ['Barbell'], defaultUnit: 'reps', difficulty: 'advanced' },
    { id: 'pin-squat-barbell', name: 'Barbell Pin Squat', category: ExerciseCategory.Strength, muscleGroups: ['Legs'], equipment: ['Barbell', 'Other'], defaultUnit: 'reps', difficulty: 'advanced' },
    { id: 'safety-bar-squat', name: 'Safety Bar Squat', category: ExerciseCategory.Strength, muscleGroups: ['Legs', 'Back'], equipment: ['Barbell'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'high-bar-squat-barbell', name: 'High Bar Barbell Squat', category: ExerciseCategory.Strength, muscleGroups: ['Quads', 'Glutes'], equipment: ['Barbell'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'low-bar-squat-barbell', name: 'Low Bar Barbell Squat', category: ExerciseCategory.Strength, muscleGroups: ['Glutes', 'Posterior Chain'], equipment: ['Barbell'], defaultUnit: 'reps', difficulty: 'advanced' },
    { id: 'sumo-squat-barbell', name: 'Barbell Sumo Squat', category: ExerciseCategory.Strength, muscleGroups: ['Glutes', 'Adductors'], equipment: ['Barbell'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'dumbbell-squat', name: 'Dumbbell Squat', category: ExerciseCategory.Strength, muscleGroups: ['Legs'], equipment: ['Dumbbell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'pistol-squat-weighted', name: 'Weighted Pistol Squat', category: ExerciseCategory.Strength, muscleGroups: ['Legs', 'Core'], equipment: ['Dumbbell'], defaultUnit: 'reps', difficulty: 'advanced' },
    { id: ' Cossack-squat-bodyweight', name: 'Cossack Squat', category: ExerciseCategory.Mobility, muscleGroups: ['Legs', 'Adductors'], equipment: ['None'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'cossack-squat-weighted', name: 'Weighted Cossack Squat', category: ExerciseCategory.Strength, muscleGroups: ['Legs', 'Adductors'], equipment: ['Kettlebell'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'jumping-lunge', name: 'Jumping Lunges', category: ExerciseCategory.Plyometrics, muscleGroups: ['Legs'], equipment: ['None'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'reverse-lunge-barbell', name: 'Barbell Reverse Lunge', category: ExerciseCategory.Strength, muscleGroups: ['Legs', 'Glutes'], equipment: ['Barbell'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'forward-lunge-barbell', name: 'Barbell Forward Lunge', category: ExerciseCategory.Strength, muscleGroups: ['Legs', 'Glutes'], equipment: ['Barbell'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'curtsy-lunge-dumbbell', name: 'Dumbbell Curtsy Lunge', category: ExerciseCategory.Strength, muscleGroups: ['Glutes'], equipment: ['Dumbbell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'walking-lunge-weighted-vest', name: 'Weighted Vest Walking Lunge', category: ExerciseCategory.Strength, muscleGroups: ['Legs', 'Glutes'], equipment: ['Other'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'overhead-lunge-dumbbell', name: 'Dumbbell Overhead Lunge', category: ExerciseCategory.Strength, muscleGroups: ['Shoulders', 'Legs', 'Core'], equipment: ['Dumbbell'], defaultUnit: 'reps', difficulty: 'advanced' },
    { id: 'overhead-lunge-barbell', name: 'Barbell Overhead Lunge', category: ExerciseCategory.Strength, muscleGroups: ['Full Body'], equipment: ['Barbell'], defaultUnit: 'reps', difficulty: 'advanced' },
    { id: 'single-leg-leg-extension', name: 'Single-Leg Extension Machine', category: ExerciseCategory.Strength, muscleGroups: ['Quads'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'single-leg-curl-lying', name: 'Single-Leg Lying Curl Machine', category: ExerciseCategory.Strength, muscleGroups: ['Hamstrings'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'single-leg-curl-seated', name: 'Single-Leg Seated Curl Machine', category: ExerciseCategory.Strength, muscleGroups: ['Hamstrings'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'single-arm-barbell-curl', name: 'Single-Arm Barbell Bicep Curl', category: ExerciseCategory.Strength, muscleGroups: ['Biceps'], equipment: ['Barbell'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'seated-dumbbell-curl', name: 'Seated Dumbbell Bicep Curl', category: ExerciseCategory.Strength, muscleGroups: ['Biceps'], equipment: ['Dumbbell', 'Bench'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'waiter-curl-dumbbell', name: 'Dumbbell Waiter Curl', category: ExerciseCategory.Strength, muscleGroups: ['Biceps'], equipment: ['Dumbbell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'cable-curl-ez-bar', name: 'Cable Bicep Curl (EZ-Bar)', category: ExerciseCategory.Strength, muscleGroups: ['Biceps'], equipment: ['Cable'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'cable-curl-unilateral', name: 'Single-Arm Cable Bicep Curl', category: ExerciseCategory.Strength, muscleGroups: ['Biceps'], equipment: ['Cable'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'high-cable-bicep-curl', name: 'High Cable Bicep Curl', category: ExerciseCategory.Strength, muscleGroups: ['Biceps'], equipment: ['Cable'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'preacher-curl-dumbbell', name: 'Dumbbell Preacher Curl', category: ExerciseCategory.Strength, muscleGroups: ['Biceps'], equipment: ['Dumbbell', 'Bench'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'preacher-curl-machine', name: 'Machine Preacher Curl', category: ExerciseCategory.Strength, muscleGroups: ['Biceps'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'hammer-curl-cable', name: 'Cable Hammer Curl (Rope)', category: ExerciseCategory.Strength, muscleGroups: ['Biceps', 'Forearms'], equipment: ['Cable'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'hammer-curl-preacher', name: 'Hammer Preacher Curl', category: ExerciseCategory.Strength, muscleGroups: ['Biceps', 'Forearms'], equipment: ['Dumbbell', 'Bench'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'brachialis-curl-cross-body', name: 'Cross Body Hammer Curl', category: ExerciseCategory.Strength, muscleGroups: ['Biceps', 'Forearms'], equipment: ['Dumbbell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'reverse-grip-cable-curl', name: 'Reverse Grip Cable Curl', category: ExerciseCategory.Strength, muscleGroups: ['Forearms'], equipment: ['Cable'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'concentration-curl-cable', name: 'Cable Concentration Curl', category: ExerciseCategory.Strength, muscleGroups: ['Biceps'], equipment: ['Cable'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'tricep-pushdown-v-bar', name: 'Tricep V-Bar Pushdown', category: ExerciseCategory.Strength, muscleGroups: ['Triceps'], equipment: ['Cable'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'tricep-pushdown-single-arm-reverse', name: 'Single-Arm Reverse Grip Pushdown', category: ExerciseCategory.Strength, muscleGroups: ['Triceps'], equipment: ['Cable'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'skullcrusher-barbell', name: 'Barbell Skullcrusher', category: ExerciseCategory.Strength, muscleGroups: ['Triceps'], equipment: ['Barbell', 'Bench'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'skullcrusher-dumbbell', name: 'Dumbbell Skullcrusher', category: ExerciseCategory.Strength, muscleGroups: ['Triceps'], equipment: ['Dumbbell', 'Bench'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'skullcrusher-cable', name: 'Cable Skullcrusher', category: ExerciseCategory.Strength, muscleGroups: ['Triceps'], equipment: ['Cable', 'Bench'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'overhead-tricep-extension-ez-bar', name: 'Overhead EZ-Bar Tricep Extension', category: ExerciseCategory.Strength, muscleGroups: ['Triceps'], equipment: ['Barbell'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'overhead-tricep-extension-barbell', name: 'Overhead Barbell Tricep Extension', category: ExerciseCategory.Strength, muscleGroups: ['Triceps'], equipment: ['Barbell'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'tricep-press-machine', name: 'Machine Tricep Pressdown', category: ExerciseCategory.Strength, muscleGroups: ['Triceps'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'tate-press', name: 'Dumbbell Tate Press', category: ExerciseCategory.Strength, muscleGroups: ['Triceps'], equipment: ['Dumbbell', 'Bench'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'kickback-cable', name: 'Single-Arm Cable Tricep Kickback', category: ExerciseCategory.Strength, muscleGroups: ['Triceps'], equipment: ['Cable'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'french-press-barbell', name: 'Barbell French Press', category: ExerciseCategory.Strength, muscleGroups: ['Triceps'], equipment: ['Barbell', 'Bench'], defaultUnit: 'reps', difficulty: 'intermediate' },
    { id: 'ez-bar-wrist-curl', name: 'EZ-Bar Wrist Curl', category: ExerciseCategory.Strength, muscleGroups: ['Forearms'], equipment: ['Barbell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'ez-bar-reverse-wrist-curl', name: 'EZ-Bar Reverse Wrist Curl', category: ExerciseCategory.Strength, muscleGroups: ['Forearms'], equipment: ['Barbell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'wrist-curl-dumbbell-unilateral', name: 'Single-Arm Dumbbell Wrist Curl', category: ExerciseCategory.Strength, muscleGroups: ['Forearms'], equipment: ['Dumbbell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'wrist-roller', name: 'Wrist Roller', category: ExerciseCategory.Strength, muscleGroups: ['Forearms'], equipment: ['Other'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'reverse-wrist-curl-dumbbell', name: 'Dumbbell Reverse Wrist Curl', category: ExerciseCategory.Strength, muscleGroups: ['Forearms'], equipment: ['Dumbbell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'forearm-rotation-dumbbell', name: 'Dumbbell Forearm Rotation', category: ExerciseCategory.Mobility, muscleGroups: ['Forearms'], equipment: ['Dumbbell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'radial-deviation-dumbbell', name: 'Dumbbell Radial Deviation', category: ExerciseCategory.Strength, muscleGroups: ['Forearms'], equipment: ['Dumbbell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'ulnar-deviation-dumbbell', name: 'Dumbbell Ulnar Deviation', category: ExerciseCategory.Strength, muscleGroups: ['Forearms'], equipment: ['Dumbbell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'behind-the-back-wrist-curl', name: 'Behind the Back Barbell Wrist Curl', category: ExerciseCategory.Strength, muscleGroups: ['Forearms'], equipment: ['Barbell'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'pinch-grip-hold', name: 'Plate Pinch Grip Hold', category: ExerciseCategory.Strength, muscleGroups: ['Grip', 'Forearms'], equipment: ['Plate'], defaultUnit: 's', difficulty: 'intermediate' },
    { id: 'wrist-extension-machine', name: 'Machine Wrist Extension', category: ExerciseCategory.Strength, muscleGroups: ['Forearms'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'beginner' },
    { id: 'wrist-flexion-machine', name: 'Machine Wrist Flexion', category: ExerciseCategory.Strength, muscleGroups: ['Forearms'], equipment: ['Machine'], defaultUnit: 'reps', difficulty: 'beginner' },
];
