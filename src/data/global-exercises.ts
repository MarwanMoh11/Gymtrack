import { GlobalExercise } from '../types/workout';

export const globalExercises: GlobalExercise[] = [
    // --- CHEST ---
    {
        id: 'barbell-bench-press',
        name: 'Barbell Bench Press',
        category: 'strength',
        muscleGroups: ['Chest', 'Triceps', 'Front Delts'],
        equipment: ['barbell', 'bench'],
        defaultUnit: 'reps',
        description: 'The king of upper body exercises. Lie on a flat bench and press the weight up.',
        videoUrl: 'https://www.youtube.com/embed/rT7DgCr-3pg',
        difficulty: 'intermediate'
    },
    {
        id: 'incline-dumbbell-press',
        name: 'Incline Dumbbell Press',
        category: 'strength',
        muscleGroups: ['Upper Chest', 'Triceps', 'Front Delts'],
        equipment: ['dumbbells', 'bench'],
        defaultUnit: 'reps',
        description: 'Set bench to 30-45 degrees. Press dumbbells overhead to target upper chest.',
        difficulty: 'beginner'
    },
    {
        id: 'chest-dip',
        name: 'Chest Dip',
        category: 'strength',
        muscleGroups: ['Lower Chest', 'Triceps', 'Front Delts'],
        equipment: ['dip_bars'],
        defaultUnit: 'reps',
        description: 'Lean forward to target chest. Lower until shoulders are below elbows.',
        difficulty: 'intermediate'
    },
    {
        id: 'cable-crossover',
        name: 'Cable Crossover',
        category: 'strength',
        muscleGroups: ['Chest'],
        equipment: ['cable_machine'],
        defaultUnit: 'reps',
        description: 'Stand in center of cable machine, pull handles together across body.',
        difficulty: 'intermediate'
    },
    {
        id: 'push-up',
        name: 'Push-Up',
        category: 'bodyweight',
        muscleGroups: ['Chest', 'Core', 'Triceps'],
        equipment: ['none'],
        defaultUnit: 'reps',
        description: 'Standard push-up. Keep core tight and back straight.',
        difficulty: 'beginner'
    },

    // --- BACK ---
    {
        id: 'deadlift',
        name: 'Deadlift',
        category: 'strength',
        muscleGroups: ['Back', 'Hamstrings', 'Glutes', 'Core'],
        equipment: ['barbell'],
        defaultUnit: 'reps',
        description: 'Compound lift. Lift bar from floor to hip level. Keep back neutral.',
        difficulty: 'advanced'
    },
    {
        id: 'pull-up',
        name: 'Pull-Up',
        category: 'bodyweight',
        muscleGroups: ['Lats', 'Biceps'],
        equipment: ['pull_up_bar'],
        defaultUnit: 'reps',
        description: 'Pull chin over bar. Palms facing away. Full range of motion.',
        difficulty: 'intermediate'
    },
    {
        id: 'barbell-row',
        name: 'Barbell Row',
        category: 'strength',
        muscleGroups: ['Upper Back', 'Lats', 'Biceps'],
        equipment: ['barbell'],
        defaultUnit: 'reps',
        description: 'Bend over at hips, pull bar to stomach. Squeeze shoulder blades.',
        difficulty: 'intermediate'
    },
    {
        id: 'lat-pulldown',
        name: 'Lat Pulldown',
        category: 'strength',
        muscleGroups: ['Lats', 'Biceps'],
        equipment: ['cable_machine'],
        defaultUnit: 'reps',
        description: 'Seated pull-down. Pull bar to upper chest.',
        difficulty: 'beginner'
    },
    {
        id: 'seated-cable-row',
        name: 'Seated Cable Row',
        category: 'strength',
        muscleGroups: ['Mid Back', 'Lats', 'Biceps'],
        equipment: ['cable_machine'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },

    // --- LEGS (Quads/Glutes/Hams) ---
    {
        id: 'barbell-back-squat',
        name: 'Barbell Back Squat',
        category: 'strength',
        muscleGroups: ['Quads', 'Glutes', 'Core'],
        equipment: ['barbell', 'squat_rack'],
        defaultUnit: 'reps',
        description: 'Bar on traps. Squat down until hips are below knees.',
        difficulty: 'advanced'
    },
    {
        id: 'leg-press',
        name: 'Leg Press',
        category: 'strength',
        muscleGroups: ['Quads', 'Glutes'],
        equipment: ['leg_press'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'romanian-deadlift',
        name: 'Romanian Deadlift (RDL)',
        category: 'strength',
        muscleGroups: ['Hamstrings', 'Glutes', 'Lower Back'],
        equipment: ['barbell'],
        defaultUnit: 'reps',
        description: 'Hinge at hips, slight knee bend. Lower bar until hamstring stretch.',
        difficulty: 'intermediate'
    },
    {
        id: 'bulgarian-split-squat',
        name: 'Bulgarian Split Squat',
        category: 'strength',
        muscleGroups: ['Quads', 'Glutes'],
        equipment: ['dumbbells', 'bench'],
        defaultUnit: 'reps',
        description: 'Rear foot elevated. Squat down with front leg.',
        difficulty: 'intermediate'
    },
    {
        id: 'leg-extension',
        name: 'Leg Extension',
        category: 'strength',
        muscleGroups: ['Quads'],
        equipment: ['other'], // Machine
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'lying-leg-curl',
        name: 'Lying Leg Curl',
        category: 'strength',
        muscleGroups: ['Hamstrings'],
        equipment: ['other'], // Machine
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },

    // --- SHOULDERS ---
    {
        id: 'overhead-press',
        name: 'Overhead Press (OHP)',
        category: 'strength',
        muscleGroups: ['Shoulders', 'Triceps'],
        equipment: ['barbell'],
        defaultUnit: 'reps',
        description: 'Standing press. Bar from chest to overhead lockout.',
        difficulty: 'intermediate'
    },
    {
        id: 'dumbbell-lateral-raise',
        name: 'Dumbbell Lateral Raise',
        category: 'strength',
        muscleGroups: ['Side Delts'],
        equipment: ['dumbbells'],
        defaultUnit: 'reps',
        description: 'Raise arms to side until parallel with floor.',
        difficulty: 'beginner'
    },
    {
        id: 'face-pull',
        name: 'Face Pull',
        category: 'strength',
        muscleGroups: ['Rear Delts', 'Rotator Cuff'],
        equipment: ['cable_machine'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },

    // --- ARMS ---
    {
        id: 'barbell-curl',
        name: 'Barbell Curl',
        category: 'strength',
        muscleGroups: ['Biceps'],
        equipment: ['barbell'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'tricep-pushdown',
        name: 'Tricep Rope Pushdown',
        category: 'strength',
        muscleGroups: ['Triceps'],
        equipment: ['cable_machine'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'hammer-curl',
        name: 'Dumbbell Hammer Curl',
        category: 'strength',
        muscleGroups: ['Biceps', 'Forearms'],
        equipment: ['dumbbells'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'skullcrusher',
        name: 'Ez-Bar Skullcrusher',
        category: 'strength',
        muscleGroups: ['Triceps'],
        equipment: ['barbell', 'bench'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },

    // --- CORE ---
    {
        id: 'plank',
        name: 'Plank',
        category: 'core',
        muscleGroups: ['Abs', 'Core'],
        equipment: ['none'],
        defaultUnit: 's',
        difficulty: 'beginner'
    },
    {
        id: 'hanging-leg-raise',
        name: 'Hanging Leg Raise',
        category: 'core',
        muscleGroups: ['Abs', 'Hip Flexors'],
        equipment: ['pull_up_bar'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'cable-crunch',
        name: 'Cable Crunch',
        category: 'core',
        muscleGroups: ['Abs'],
        equipment: ['cable_machine'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },

    // --- CARDIO / HYBRID ---
    {
        id: 'treadmill-run',
        name: 'Treadmill Run',
        category: 'cardio',
        muscleGroups: ['Legs', 'Cardiovascular'],
        equipment: ['cardio_machine'],
        defaultUnit: 'min',
        difficulty: 'beginner'
    },
    {
        id: 'rowing-machine',
        name: 'Rowing Machine',
        category: 'cardio',
        muscleGroups: ['Full Body'],
        equipment: ['cardio_machine'],
        defaultUnit: 'min',
        difficulty: 'intermediate'
    },
    {
        id: 'burpees',
        name: 'Burpees',
        category: 'plyometrics',
        muscleGroups: ['Full Body'],
        equipment: ['none'],
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },
    {
        id: 'box-jump',
        name: 'Box Jump',
        category: 'plyometrics',
        muscleGroups: ['Legs'],
        equipment: ['other'], // Box
        defaultUnit: 'reps',
        difficulty: 'intermediate'
    },

    // --- MOBILITY ---
    {
        id: 'cat-cow',
        name: 'Cat-Cow Stretch',
        category: 'mobility',
        muscleGroups: ['Spine'],
        equipment: ['yoga_mat'],
        defaultUnit: 'reps',
        difficulty: 'beginner'
    },
    {
        id: 'foam-roll-quads',
        name: 'Foam Roll - Quads',
        category: 'mobility',
        muscleGroups: ['Quads'],
        equipment: ['foam_roller'],
        defaultUnit: 'min',
        difficulty: 'beginner'
    },
];
