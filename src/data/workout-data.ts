
import type { WeeklyPlan, Exercise } from '@/types/workout';

export const weeklyPlan: WeeklyPlan = [
  {
    id: 'monday',
    dayName: 'Monday',
    title: 'Upper Body Push',
    exercises: [
      {
        id: 'mon-ex1', name: 'Incline DB Bench Press', targetWeight: '22.5 kg', unit: 'reps',
        description: 'A variation of the bench press that targets the upper chest muscles more effectively due to the inclined angle of the bench. Also works the front deltoids and triceps.',
        videoUrl: 'https://www.youtube.com/embed/8iPEnn-ltC8',
        muscleGroups: ['Chest (Upper)', 'Shoulders (Front)', 'Triceps'],
        sets: [
          { id: 'mon-ex1-set1', targetReps: 12 },
          { id: 'mon-ex1-set2', targetReps: 10 },
          { id: 'mon-ex1-set3', targetReps: 8 },
        ],
      },
      {
        id: 'mon-ex2', name: 'Smith Machine Incline Press', targetWeight: '17.5 kg', unit: 'reps',
        description: 'Similar to the Incline DB Bench Press but performed on a Smith machine, which guides the barbell along a fixed path. This can help with stability and focusing on the target muscles.',
        videoUrl: 'https://www.youtube.com/embed/DbjgKTnXnL0',
        muscleGroups: ['Chest (Upper)', 'Shoulders (Front)', 'Triceps'],
        sets: [
          { id: 'mon-ex2-set1', targetReps: 10 },
          { id: 'mon-ex2-set2', targetReps: 8 },
          { id: 'mon-ex2-set3', targetReps: 8 },
        ],
      },
      {
        id: 'mon-ex3', name: 'Dips', targetWeight: '0 kg (bodyweight)', unit: 'reps',
        description: 'A compound bodyweight exercise that primarily targets the triceps and chest. Performed using parallel bars.',
        videoUrl: 'https://www.youtube.com/embed/2z8JmcrW-As', // Example video for Dips
        muscleGroups: ['Triceps', 'Chest (Lower)', 'Shoulders (Front)'],
        sets: [
          { id: 'mon-ex3-set1', targetReps: 8 },
          { id: 'mon-ex3-set2', targetReps: 6 },
          { id: 'mon-ex3-set3', targetReps: 6 },
        ],
      },
      {
        id: 'mon-ex4', name: 'Seated Shoulder Press', targetWeight: '65 kg', unit: 'reps',
        description: 'An overhead pressing exercise, usually performed with a barbell or dumbbells while seated, targeting the deltoid muscles.',
        muscleGroups: ['Shoulders (All Heads)', 'Triceps'],
        videoUrl: 'https://www.youtube.com/embed/qEwKCR5JCog',
        sets: [
          { id: 'mon-ex4-set1', targetReps: 12 },
          { id: 'mon-ex4-set2', targetReps: 10 },
          { id: 'mon-ex4-set3', targetReps: 8 },
        ],
      },
      {
        id: 'mon-ex5', name: 'Cable Fly (rope)', targetWeight: '2nd stack', unit: 'reps',
        description: 'An isolation exercise for the chest muscles, performed using a cable machine with a rope attachment. Provides constant tension throughout the movement.',
        videoUrl: 'https://www.youtube.com/embed/Iwe6AmxVf7o', // Example, may need specific rope variant
        muscleGroups: ['Chest'],
        sets: [
          { id: 'mon-ex5-set1', targetReps: 12 },
          { id: 'mon-ex5-set2', targetReps: 10 },
          { id: 'mon-ex5-set3', targetReps: 8 },
        ],
      },
      {
        id: 'mon-ex6', name: 'Rear-Delt Cable Fly', targetWeight: '12 kg', unit: 'reps',
        description: 'Targets the posterior (rear) deltoids using a cable machine. Important for shoulder health and a well-rounded physique.',
        videoUrl: 'https://www.youtube.com/embed/EA7u4Q_8HQ0',
        muscleGroups: ['Shoulders (Rear)', 'Upper Back'],
        sets: [
          { id: 'mon-ex6-set1', targetReps: 12 },
          { id: 'mon-ex6-set2', targetReps: 12 },
          { id: 'mon-ex6-set3', targetReps: '—' }, // Indicates 'to failure' or similar
        ],
      },
      {
        id: 'mon-ex7', name: 'Triceps Rope Pushdown', targetWeight: '5th stack', unit: 'reps',
        description: 'An isolation exercise for the triceps using a cable machine and a rope attachment.',
        videoUrl: 'https://www.youtube.com/embed/vB5OHro6kAA',
        muscleGroups: ['Triceps'],
        sets: [
          { id: 'mon-ex7-set1', targetReps: '—' },
          { id: 'mon-ex7-set2', targetReps: '—' },
          { id: 'mon-ex7-set3', targetReps: '—' },
        ],
      },
      {
        id: 'mon-ex8', name: 'Core – Plank', unit: 's', isCore: true, notes: 'Duration: 60–75 s',
        description: 'An isometric core strength exercise that involves maintaining a position similar to a push-up for the maximum possible time.',
        videoUrl: 'https://www.youtube.com/embed/ASdvN_XEl_c',
        muscleGroups: ['Core (Abs, Obliques, Lower Back)'],
        sets: [
          { id: 'mon-ex8-set1', targetReps: 60, unit: 's' },
          { id: 'mon-ex8-set2', targetReps: 60, unit: 's' },
          { id: 'mon-ex8-set3', targetReps: 75, unit: 's' },
        ],
      },
    ],
  },
  {
    id: 'tuesday',
    dayName: 'Tuesday',
    title: 'Upper Body Pull',
    exercises: [
      {
        id: 'tue-ex1', name: 'Wide Lat Pulldown', targetWeight: '12th stack', unit: 'reps',
        description: 'A compound exercise targeting the latissimus dorsi (lats) using a cable pulldown machine with a wide grip.',
        muscleGroups: ['Lats', 'Biceps', 'Upper Back'],
        videoUrl: 'https://www.youtube.com/embed/lueEJGjTuPQ',
        sets: [
          { id: 'tue-ex1-set1', targetReps: 12 },
          { id: 'tue-ex1-set2', targetReps: 10 },
          { id: 'tue-ex1-set3', targetReps: 8 },
        ],
      },
      {
        id: 'tue-ex2', name: 'Neutral-Grip Pulldown', targetWeight: '11th stack', unit: 'reps', notes: 'Superset A',
        description: 'A variation of the lat pulldown using a neutral (palms facing each other) grip, which can alter muscle emphasis slightly.',
        videoUrl: 'https://www.youtube.com/embed/0oeEUm3jXyA', // Example video
        muscleGroups: ['Lats', 'Biceps', 'Upper Back'],
        sets: [
          { id: 'tue-ex2-set1', targetReps: 12 },
          { id: 'tue-ex2-set2', targetReps: 10 },
          { id: 'tue-ex2-set3', targetReps: 8 },
        ],
      },
      {
        id: 'tue-ex3', name: 'Face Pulls', targetWeight: 'cable', unit: 'reps', notes: 'Superset B',
        description: 'An exercise for the upper back and rear deltoids, typically performed with a rope attachment on a cable machine. Excellent for shoulder health and posture.',
        videoUrl: 'https://www.youtube.com/embed/rep-qVOkqgk',
        muscleGroups: ['Shoulders (Rear)', 'Traps', 'Rhomboids'],
        sets: [
          { id: 'tue-ex3-set1', targetReps: 15 },
          { id: 'tue-ex3-set2', targetReps: 13 },
          { id: 'tue-ex3-set3', targetReps: 12 },
        ],
      },
      {
        id: 'tue-ex4', name: 'Half-Kneeling One-Arm Lat Pulldown (each arm)', targetWeight: '5th stack', unit: 'reps',
        description: 'A unilateral (one-arm) lat pulldown variation performed in a half-kneeling stance, which can improve core stability and isolate each side of the back.',
        videoUrl: 'https://www.youtube.com/embed/LqXk9a_h2H0', // Example video
        muscleGroups: ['Lats', 'Biceps', 'Core'],
        sets: [
          { id: 'tue-ex4-set1', targetReps: 12 },
          { id: 'tue-ex4-set2', targetReps: 10 },
          { id: 'tue-ex4-set3', targetReps: 8 },
        ],
      },
      {
        id: 'tue-ex5', name: 'Dumbbell Preacher Curl (each arm)', targetWeight: '10 kg', unit: 'reps',
        description: 'An isolation exercise for the biceps, performed with a dumbbell on a preacher bench to minimize momentum and maximize bicep engagement.',
        videoUrl: 'https://www.youtube.com/embed/jJk_igF9250',
        muscleGroups: ['Biceps'],
        sets: [
          { id: 'tue-ex5-set1', targetReps: 12 },
          { id: 'tue-ex5-set2', targetReps: 10 },
          { id: 'tue-ex5-set3', targetReps: 8 },
        ],
      },
      {
        id: 'tue-ex6', name: 'Barbell Preacher Curl', targetWeight: '7.5 kg each side', unit: 'reps',
        description: 'Similar to the dumbbell preacher curl, but performed with a barbell, allowing for potentially heavier loads.',
        videoUrl: 'https://www.youtube.com/embed/f_B5E30TT3o',
        muscleGroups: ['Biceps'],
        sets: [
          { id: 'tue-ex6-set1', targetReps: 12 },
          { id: 'tue-ex6-set2', targetReps: 10 },
          { id: 'tue-ex6-set3', targetReps: 8 },
        ],
      },
      {
        id: 'tue-ex7', name: 'Core – Hanging Leg Raises', unit: 'reps', isCore: true,
        description: 'A challenging core exercise performed by hanging from a bar and raising the legs towards the torso. Targets the lower abs and hip flexors.',
        videoUrl: 'https://www.youtube.com/embed/1A0Sqg_M39k',
        muscleGroups: ['Abs (Lower)', 'Hip Flexors'],
        sets: [
          { id: 'tue-ex7-set1', targetReps: 15 },
          { id: 'tue-ex7-set2', targetReps: 12 },
          { id: 'tue-ex7-set3', targetReps: 10 },
        ],
      },
    ],
  },
  {
    id: 'wednesday',
    dayName: 'Wednesday',
    title: 'Lower Body',
    exercises: [
      {
        id: 'wed-ex1', name: 'Hamstring Curl', targetWeight: '22 kg', unit: 'reps', notes: 'Superset A',
        description: 'An isolation exercise for the hamstrings, typically performed on a leg curl machine (seated or lying).',
        muscleGroups: ['Hamstrings'],
        videoUrl: 'https://www.youtube.com/embed/F488k67BTmA',
        sets: [
          { id: 'wed-ex1-set1', targetReps: 12 },
          { id: 'wed-ex1-set2', targetReps: 10 },
          { id: 'wed-ex1-set3', targetReps: 8 },
        ],
      },
      {
        id: 'wed-ex2', name: 'Romanian Deadlift', targetWeight: '15 kg', unit: 'reps', notes: 'Superset B',
        description: 'A hinge movement that primarily targets the hamstrings and glutes, with secondary involvement of the lower back. Performed with a barbell or dumbbells.',
        videoUrl: 'https://www.youtube.com/embed/JCXUYuzwNrM',
        muscleGroups: ['Hamstrings', 'Glutes', 'Lower Back'],
        sets: [
          { id: 'wed-ex2-set1', targetReps: 12 },
          { id: 'wed-ex2-set2', targetReps: 10 },
          { id: 'wed-ex2-set3', targetReps: 8 },
        ],
      },
      {
        id: 'wed-ex3', name: 'Leg Press', targetWeight: '60 kg', unit: 'reps',
        description: 'A compound lower body exercise performed on a leg press machine. Targets quads, hamstrings, and glutes depending on foot placement.',
        videoUrl: 'https://www.youtube.com/embed/IZxyjW7MPJQ',
        muscleGroups: ['Quads', 'Hamstrings', 'Glutes'],
        sets: [
          { id: 'wed-ex3-set1', targetReps: 12 },
          { id: 'wed-ex3-set2', targetReps: 10 },
          { id: 'wed-ex3-set3', targetReps: 8 },
        ],
      },
      {
        id: 'wed-ex4', name: 'Smith Machine Squats', targetWeight: '22 kg', unit: 'reps',
        description: 'Squats performed on a Smith machine, which guides the barbell. Can allow for different foot placements to target muscles differently compared to free-weight squats.',
        videoUrl: 'https://www.youtube.com/embed/VUX-Ag3R5R4',
        muscleGroups: ['Quads', 'Glutes', 'Hamstrings'],
        sets: [
          { id: 'wed-ex4-set1', targetReps: 12 },
          { id: 'wed-ex4-set2', targetReps: 10 },
          { id: 'wed-ex4-set3', targetReps: 8 },
        ],
      },
      {
        id: 'wed-ex5', name: 'Leg Extension', targetWeight: '25 kg', unit: 'reps',
        description: 'An isolation exercise for the quadriceps muscles, performed on a leg extension machine.',
        videoUrl: 'https://www.youtube.com/embed/YyvSfVjQeL0',
        muscleGroups: ['Quads'],
        sets: [
          { id: 'wed-ex5-set1', targetReps: 15 },
          { id: 'wed-ex5-set2', targetReps: 13 },
          { id: 'wed-ex5-set3', targetReps: 12 },
        ],
      },
      {
        id: 'wed-ex6', name: 'Glute Machine or DB Hip Thrust', targetWeight: '45 kg', unit: 'reps',
        description: 'Exercises focusing on the gluteal muscles. Hip thrusts are typically performed with a barbell across the hips.',
        videoUrl: 'https://www.youtube.com/embed/xDmFkJxPzeM', // DB Hip Thrust example
        muscleGroups: ['Glutes', 'Hamstrings'],
        sets: [
          { id: 'wed-ex6-set1', targetReps: 15 },
          { id: 'wed-ex6-set2', targetReps: 13 },
          { id: 'wed-ex6-set3', targetReps: 12 },
        ],
      },
      {
        id: 'wed-ex7', name: 'Calf Raises (Smith or DB)', targetWeight: 'bodyweight or added', unit: 'reps',
        description: 'An isolation exercise for the calf muscles (gastrocnemius and soleus). Can be done standing or seated, with or without weight.',
        videoUrl: 'https://www.youtube.com/embed/JbyjNymZOt0', // Standing DB Calf Raise
        muscleGroups: ['Calves'],
        sets: [
          { id: 'wed-ex7-set1', targetReps: 20 },
          { id: 'wed-ex7-set2', targetReps: 18 },
          { id: 'wed-ex7-set3', targetReps: 15 },
        ],
      },
      {
        id: 'wed-ex8', name: 'Core – Ab Wheel Rollouts or Cable Crunches', unit: 'reps', isCore: true,
        description: 'Ab wheel rollouts are a challenging core exercise engaging the entire abdominal wall. Cable crunches are a weighted abdominal exercise.',
        videoUrl: 'https://www.youtube.com/embed/sVsrKCSqYic', // Ab Wheel
        muscleGroups: ['Abs', 'Core'],
        sets: [
          { id: 'wed-ex8-set1', targetReps: 15 },
          { id: 'wed-ex8-set2', targetReps: 13 },
          { id: 'wed-ex8-set3', targetReps: 12 },
        ],
      },
    ],
  },
  {
    id: 'thursday',
    dayName: 'Thursday',
    title: 'Mixed Accessory & Conditioning',
    exercises: [
      {
        id: 'thu-ex1', name: 'Weighted Chin-Ups', targetWeight: '0', unit: 'reps',
        description: 'A variation of the pull-up with a supinated (underhand) grip, which places more emphasis on the biceps. Can be done with added weight.',
        videoUrl: 'https://www.youtube.com/embed/ZUndn_jJqM0', // Weighted Chin-up
        muscleGroups: ['Lats', 'Biceps', 'Upper Back'],
        sets: [
          { id: 'thu-ex1-set1', targetReps: 8 },
          { id: 'thu-ex1-set2', targetReps: 6 },
          { id: 'thu-ex1-set3', targetReps: 6 },
        ],
      },
      {
        id: 'thu-ex2', name: 'Cable Face Pulls', targetWeight: 'before last stack', unit: 'reps',
        description: 'An exercise for the upper back and rear deltoids, typically performed with a rope attachment on a cable machine. Excellent for shoulder health and posture.',
        videoUrl: 'https://www.youtube.com/embed/rep-qVOkqgk',
        muscleGroups: ['Shoulders (Rear)', 'Traps', 'Rhomboids'],
        sets: [
          { id: 'thu-ex2-set1', targetReps: 12 },
          { id: 'thu-ex2-set2', targetReps: 10 },
          { id: 'thu-ex2-set3', targetReps: 8 },
        ],
      },
      {
        id: 'thu-ex3', name: 'Incline DB Press', targetWeight: '17.5 kg', unit: 'reps',
        description: 'A variation of the bench press that targets the upper chest muscles more effectively due to the inclined angle of the bench. Also works the front deltoids and triceps.',
        videoUrl: 'https://www.youtube.com/embed/8iPEnn-ltC8',
        muscleGroups: ['Chest (Upper)', 'Shoulders (Front)', 'Triceps'],
        sets: [
          { id: 'thu-ex3-set1', targetReps: 12 },
          { id: 'thu-ex3-set2', targetReps: 11 },
          { id: 'thu-ex3-set3', targetReps: 10 },
        ],
      },
      {
        id: 'thu-ex4', name: 'Overhead Triceps Extension', targetWeight: '6th stack', unit: 'reps',
        description: 'A triceps isolation exercise that can be performed with dumbbells, a barbell, or cables. Focuses on the long head of the triceps.',
        videoUrl: 'https://www.youtube.com/embed/POTy3A1IeA0', // DB Overhead Extension
        muscleGroups: ['Triceps'],
        sets: [
          { id: 'thu-ex4-set1', targetReps: 15 },
          { id: 'thu-ex4-set2', targetReps: 14 },
          { id: 'thu-ex4-set3', targetReps: 12 },
        ],
      },
      {
        id: 'thu-ex5', name: 'DB Lateral Raises', targetWeight: '7.5 kg', unit: 'reps',
        description: 'An isolation exercise for the lateral (side) deltoids, performed by raising dumbbells out to the sides.',
        videoUrl: 'https://www.youtube.com/embed/3VcKaXpzqRo',
        muscleGroups: ['Shoulders (Lateral)'],
        sets: [
          { id: 'thu-ex5-set1', targetReps: 15 },
          { id: 'thu-ex5-set2', targetReps: 14 },
          { id: 'thu-ex5-set3', targetReps: 12 },
        ],
      },
      {
        id: 'thu-ex6', name: 'DB/Smith Romanian Deadlift', targetWeight: '15 kg', unit: 'reps',
        description: 'A hinge movement that primarily targets the hamstrings and glutes, with secondary involvement of the lower back. Performed with a barbell or dumbbells.',
        videoUrl: 'https://www.youtube.com/embed/JCXUYuzwNrM', // RDL
        muscleGroups: ['Hamstrings', 'Glutes', 'Lower Back'],
        sets: [
          { id: 'thu-ex6-set1', targetReps: 12 },
          { id: 'thu-ex6-set2', targetReps: 10 },
          { id: 'thu-ex6-set3', targetReps: 8 },
        ],
      },
      {
        id: 'thu-ex7', name: 'Russian Twists', targetWeight: '7.5 kgs', unit: 'reps', isCore: true,
        description: 'A core exercise that targets the obliques. Performed by sitting on the floor with knees bent and twisting the torso from side to side, often with a weight.',
        videoUrl: 'https://www.youtube.com/embed/wkD8rjkodUI',
        muscleGroups: ['Obliques', 'Abs'],
        sets: [
          { id: 'thu-ex7-set1', targetReps: 20 },
          { id: 'thu-ex7-set2', targetReps: 20 },
          { id: 'thu-ex7-set3', targetReps: 20 },
        ],
      },
      {
        id: 'thu-ex8', name: 'Conditioning Finisher', isConditioning: true, unit: 'min',
        notes: '10–15 min HIIT (30 s burpees / 30 s rest)',
        description: 'High-Intensity Interval Training (HIIT) to improve cardiovascular fitness and endurance. Example: Burpees for 30 seconds, rest for 30 seconds, repeat.',
        videoUrl: 'https://www.youtube.com/embed/JZQA08SlJnM', // Burpees
        muscleGroups: ['Full Body', 'Cardio'],
        sets: [{ id: 'thu-ex8-set1', targetReps: '10-15 min' }],
      },
    ],
  },
  {
    id: 'friday',
    dayName: 'Friday',
    title: 'Calisthenics Circuit',
    notes: 'Perform as a circuit, minimal rest between pairs; 1–2 min between rounds. 3 rounds total.',
    exercises: [
      {
        id: 'fri-ex1', name: 'Pull-Ups', targetWeight: 'bodyweight', unit: 'reps',
        description: 'A compound upper body exercise where you pull your body up until your chin is over a bar. Primarily targets lats and biceps.',
        videoUrl: 'https://www.youtube.com/embed/eGo4IYlbE5g',
        muscleGroups: ['Lats', 'Biceps', 'Upper Back'],
        sets: [
          { id: 'fri-ex1-set1', targetReps: 10 },
          { id: 'fri-ex1-set2', targetReps: 8 },
          { id: 'fri-ex1-set3', targetReps: 9 },
        ],
      },
      {
        id: 'fri-ex2', name: 'Dips', targetWeight: 'bodyweight', unit: 'reps',
        description: 'A compound bodyweight exercise that primarily targets the triceps and chest. Performed using parallel bars.',
        videoUrl: 'https://www.youtube.com/embed/2z8JmcrW-As',
        muscleGroups: ['Triceps', 'Chest (Lower)', 'Shoulders (Front)'],
        sets: [
          { id: 'fri-ex2-set1', targetReps: 12 },
          { id: 'fri-ex2-set2', targetReps: 10 },
          { id: 'fri-ex2-set3', targetReps: 9 },
        ],
      },
      {
        id: 'fri-ex3', name: 'Advanced Push-Ups', targetWeight: 'bodyweight', unit: 'reps',
        description: 'Variations of the standard push-up that increase difficulty, such as decline push-ups, archer push-ups, or one-arm push-ups. Target chest, shoulders, and triceps.',
        videoUrl: 'https://www.youtube.com/embed/Pkj8LLRsoDw', // Decline Push-up
        muscleGroups: ['Chest', 'Shoulders', 'Triceps', 'Core'],
        sets: [
          { id: 'fri-ex3-set1', targetReps: 'to failure / 18' },
          { id: 'fri-ex3-set2', targetReps: 'to failure / 14' },
          { id: 'fri-ex3-set3', targetReps: 'to failure / 12' },
        ],
      },
      {
        id: 'fri-ex4', name: 'Bodyweight/Jump Squats', unit: 'reps', targetWeight: 'bodyweight',
        description: 'A lower body exercise performed using only bodyweight. Jump squats add a plyometric component for explosiveness.',
        videoUrl: 'https://www.youtube.com/embed/U4s4mEQ5VqU', // Jump Squat
        muscleGroups: ['Quads', 'Glutes', 'Hamstrings', 'Calves'],
        sets: [
          { id: 'fri-ex4-set1', targetReps: 15 },
          { id: 'fri-ex4-set2', targetReps: 13 },
          { id: 'fri-ex4-set3', targetReps: 12 },
        ],
      },
      {
        id: 'fri-ex5', name: 'Hanging Windshield Wipers or L-Sit', unit: 'reps', isCore: true, targetWeight: 'bodyweight',
        description: 'Advanced core exercises. Windshield wipers involve twisting the legs side to side while hanging. L-sits involve holding the legs straight out in front while supporting the body.',
        videoUrl: 'https://www.youtube.com/embed/PzAmVcjY2X8', // L-Sit
        muscleGroups: ['Abs', 'Obliques', 'Hip Flexors', 'Core'],
        sets: [
          { id: 'fri-ex5-set1', targetReps: '10 (or hold)' },
          { id: 'fri-ex5-set2', targetReps: '8 (or hold)' },
          { id: 'fri-ex5-set3', targetReps: '10 (or hold)' },
        ],
      },
      {
        id: 'fri-ex6', name: 'Inverted Rows', unit: 'reps', targetWeight: 'bodyweight',
        description: 'A bodyweight pulling exercise, often performed using a bar set at waist height. Targets the back and biceps.',
        videoUrl: 'https://www.youtube.com/embed/D7jvi0tN84U',
        muscleGroups: ['Upper Back', 'Lats', 'Biceps'],
        sets: [
          { id: 'fri-ex6-set1', targetReps: 10 },
          { id: 'fri-ex6-set2', targetReps: 10 },
          { id: 'fri-ex6-set3', targetReps: 10 },
        ],
      },
      {
        id: 'fri-ex7', name: 'Plank', unit: 's', isCore: true, targetWeight: 'bodyweight',
        description: 'An isometric core strength exercise that involves maintaining a position similar to a push-up for the maximum possible time.',
        videoUrl: 'https://www.youtube.com/embed/ASdvN_XEl_c',
        muscleGroups: ['Core (Abs, Obliques, Lower Back)'],
        sets: [
          { id: 'fri-ex7-set1', targetReps: 45, unit: 's' },
          { id: 'fri-ex7-set2', targetReps: 45, unit: 's' },
          { id: 'fri-ex7-set3', targetReps: 45, unit: 's' },
        ],
      },
    ],
  },
  {
    id: 'saturday',
    dayName: 'Saturday',
    title: 'Football Match Day',
    exercises: [
      {
        id: 'sat-ex1', name: 'Jog + Dynamic Warm-Up', targetWeight: 'bodyweight', isWarmup: true, isActivity: true,
        description: 'Light jogging followed by dynamic movements like leg swings and A-skips to prepare the body for intense activity.',
        muscleGroups: ['Full Body', 'Cardio'],
        sets: [
          { id: 'sat-ex1-set1', targetReps: 'Jog 5 min' },
          { id: 'sat-ex1-set2', targetReps: 'Leg swings, 10 ea leg' },
          { id: 'sat-ex1-set3', targetReps: 'A-skips, 20 m' },
        ],
      },
      {
        id: 'sat-ex2', name: 'Accelerations', targetWeight: 'bodyweight', isWarmup: true, isActivity: true,
        description: 'Short sprints with increasing speed to prepare for explosive movements during the match.',
        muscleGroups: ['Legs', 'Cardio'],
        sets: [{ id: 'sat-ex2-set1', targetReps: '3 × 20 m all‐out' }],
      },
      {
        id: 'sat-ex3', name: 'Football Match', isMatch: true, isActivity: true, targetWeight: 'N/A',
        description: 'Participation in a football (soccer) match.',
        muscleGroups: ['Full Body', 'Cardio', 'Agility'],
        sets: [{ id: 'sat-ex3-set1', targetReps: 'Match play (~90 min)' }],
      },
      {
        id: 'sat-ex4', name: 'Cool-Down Jog/Walk', targetWeight: 'bodyweight', isActivity: true,
        description: 'Light jogging or walking to gradually lower heart rate and aid recovery after the match.',
        muscleGroups: ['Full Body', 'Cardio'],
        sets: [{ id: 'sat-ex4-set1', targetReps: '10 min easy' }],
      },
      {
        id: 'sat-ex5', name: 'Static Stretch', isStretch: true, isActivity: true, targetWeight: 'N/A',
        description: 'Holding stretches for major muscle groups used during the match to improve flexibility and aid recovery.',
        muscleGroups: ['Quads', 'Hamstrings', 'Calves', 'Glutes', 'Groin'],
        sets: [
          { id: 'sat-ex5-set1', targetReps: 'Quads 30 s ea' },
          { id: 'sat-ex5-set2', targetReps: 'Hamstrings 30 s ea' },
          { id: 'sat-ex5-set3', targetReps: 'Calves 30 s ea' },
        ],
      },
    ],
  },
  {
    id: 'sunday',
    dayName: 'Sunday',
    title: 'Active Recovery',
    exercises: [
      {
        id: 'sun-ex1', name: 'Walking', isRecovery: true, isActivity: true, targetWeight: 'bodyweight',
        description: 'Low-intensity walking to promote blood flow and recovery without stressing the body.',
        muscleGroups: ['Full Body', 'Cardio'],
        sets: [{ id: 'sun-ex1-set1', targetReps: '1 hour, 10,000 Steps' }],
      },
      {
        id: 'sun-ex2', name: 'Foam-Roll Quads', targetWeight: 'bodyweight', isFoamRoll: true, isRecovery: true,
        description: 'Using a foam roller to massage and release tension in the quadriceps muscles.',
        muscleGroups: ['Quads'],
        sets: [{ id: 'sun-ex2-set1', targetReps: '2 min' }],
      },
      {
        id: 'sun-ex3', name: 'Foam-Roll Hamstrings', targetWeight: 'bodyweight', isFoamRoll: true, isRecovery: true,
        description: 'Using a foam roller to massage and release tension in the hamstring muscles.',
        muscleGroups: ['Hamstrings'],
        sets: [{ id: 'sun-ex3-set1', targetReps: '2 min' }],
      },
      {
        id: 'sun-ex4', name: 'Foam-Roll Lats', targetWeight: 'bodyweight', isFoamRoll: true, isRecovery: true,
        description: 'Using a foam roller to massage and release tension in the latissimus dorsi muscles.',
        muscleGroups: ['Lats'],
        sets: [{ id: 'sun-ex4-set1', targetReps: '2 min' }],
      },
      {
        id: 'sun-ex5', name: 'PNF Hamstring Stretch', isStretch: true, isRecovery: true, targetWeight: 'N/A',
        description: 'Proprioceptive Neuromuscular Facilitation (PNF) stretching for hamstrings, often involving a contract-relax sequence.',
        muscleGroups: ['Hamstrings'],
        sets: [{ id: 'sun-ex5-set1', targetReps: '2 × 30 s ea leg' }],
      },
      {
        id: 'sun-ex6', name: 'PNF Hip-Flexor Stretch', isStretch: true, isRecovery: true, targetWeight: 'N/A',
        description: 'PNF stretching for hip flexor muscles.',
        muscleGroups: ['Hip Flexors', 'Quads'],
        sets: [{ id: 'sun-ex6-set1', targetReps: '2 × 30 s ea side' }],
      },
      {
        id: 'sun-ex7', name: 'Shoulder Dislocates', targetWeight: 'band', isStretch: true, isRecovery: true,
        description: 'A shoulder mobility exercise using a band or stick, involving a wide circular motion of the arms.',
        muscleGroups: ['Shoulders', 'Chest'],
        sets: [{ id: 'sun-ex7-set1', targetReps: '15 reps' }],
      },
    ],
  },
];

export const getWorkoutByDay = (dayId: string) => {
  return weeklyPlan.find(day => day.id.toLowerCase() === dayId.toLowerCase());
};

// Helper function to get all unique exercises for static param generation or autocomplete
export const getAllExercisesFromPlan = (): Exercise[] => {
  const allExercisesMap = new Map<string, Exercise>();
  weeklyPlan.forEach(day => {
    day.exercises.forEach(exercise => {
      if (!allExercisesMap.has(exercise.id)) {
        allExercisesMap.set(exercise.id, exercise);
      }
    });
  });
  return Array.from(allExercisesMap.values());
};

export const getExerciseById = (exerciseId: string): Exercise | undefined => {
  for (const day of weeklyPlan) {
    const foundExercise = day.exercises.find(ex => ex.id === exerciseId);
    if (foundExercise) {
      return foundExercise;
    }
  }
  // If not found in specific days, check the comprehensive list (in case it's an exercise not yet assigned to a day but exists in a general list)
  // This part would be more relevant if we had a separate master list of exercises.
  // For now, it just re-iterates, but could be adapted if `getAllExercisesFromPlan` sourced from a different master list.
  const allExercises = getAllExercisesFromPlan();
  return allExercises.find(ex => ex.id === exerciseId);
};

// getDays is not actively used by the modified sidebar, but kept in case it's needed elsewhere.
export const getDays = () => weeklyPlan.map(day => ({ id: day.id, dayName: day.dayName, title: day.title }));
