
import type { WeeklyPlan, Exercise, NamedWorkoutPlan, WorkoutDay } from '@/types/workout';

export const defaultStrengthPlan: WeeklyPlan = [
  {
    id: 'monday',
    dayName: 'Monday',
    title: 'Upper Body Push',
    mapsToActualDayOfWeek: 1,
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
        videoUrl: 'https://www.youtube.com/embed/2z8JmcrW-As',
        muscleGroups: ['Triceps', 'Chest (Lower)', 'Shoulders (Front)'],
        sets: [
          { id: 'mon-ex3-set1', targetReps: 8 },
          { id: 'mon-ex3-set2', targetReps: 6 },
          { id: 'mon-ex3-set3', targetReps: 6 },
        ],
      },
      {
        id: 'mon-ex4', name: 'Seated Shoulder Press', targetWeight: '65 kg', unit: 'reps',
        description: 'An overhead pressing exercise, usually performed with a barbell or dumbbells while seated, targeting the deltoid muscles. Can be done with DBs (as in current video) or Barbell.',
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
        videoUrl: 'https://www.youtube.com/embed/Iwe6AmxVf7o',
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
          { id: 'mon-ex6-set3', targetReps: '—' },
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
    mapsToActualDayOfWeek: 2,
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
        videoUrl: 'https://www.youtube.com/embed/0oeEUm3jXyA',
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
        videoUrl: 'https://www.youtube.com/embed/LqXk9a_h2H0',
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
    mapsToActualDayOfWeek: 3,
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
        videoUrl: 'https://www.youtube.com/embed/xDmFkJxPzeM',
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
        videoUrl: 'https://www.youtube.com/embed/JbyjNymZOt0',
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
        videoUrl: 'https://www.youtube.com/embed/sVsrKCSqYic',
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
    mapsToActualDayOfWeek: 4,
    exercises: [
      {
        id: 'thu-ex1', name: 'Weighted Chin-Ups', targetWeight: '0', unit: 'reps',
        description: 'A variation of the pull-up with a supinated (underhand) grip, which places more emphasis on the biceps. Can be done with added weight.',
        videoUrl: 'https://www.youtube.com/embed/ZUndn_jJqM0',
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
        videoUrl: 'https://www.youtube.com/embed/POTy3A1IeA0',
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
        videoUrl: 'https://www.youtube.com/embed/JCXUYuzwNrM',
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
        videoUrl: 'https://www.youtube.com/embed/JZQA08SlJnM',
        muscleGroups: ['Full Body', 'Cardio'],
        sets: [{ id: 'thu-ex8-set1', targetReps: '10-15 min' }],
      },
    ],
  },
  {
    id: 'friday',
    dayName: 'Friday',
    title: 'Calisthenics Circuit',
    mapsToActualDayOfWeek: 5,
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
        videoUrl: 'https://www.youtube.com/embed/Pkj8LLRsoDw',
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
        videoUrl: 'https://www.youtube.com/embed/U4s4mEQ5VqU',
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
        videoUrl: 'https://www.youtube.com/embed/PzAmVcjY2X8',
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
    mapsToActualDayOfWeek: 6,
    exercises: [
      {
        id: 'sat-ex1', name: 'Jog + Dynamic Warm-Up', targetWeight: 'bodyweight', isWarmup: true, isActivity: true,
        description: 'Light jogging followed by dynamic movements like leg swings and A-skips to prepare the body for intense activity.',
        videoUrl: 'https://www.youtube.com/embed/nFo5dK_8g-k',
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
        videoUrl: 'https://www.youtube.com/embed/placeholder',
        muscleGroups: ['Legs', 'Cardio'],
        sets: [{ id: 'sat-ex2-set1', targetReps: '3 × 20 m all‐out' }],
      },
      {
        id: 'sat-ex3', name: 'Football Match', isMatch: true, isActivity: true, targetWeight: 'N/A',
        description: 'Participation in a football (soccer) match.',
        videoUrl: 'https://www.youtube.com/embed/placeholder',
        muscleGroups: ['Full Body', 'Cardio', 'Agility'],
        sets: [{ id: 'sat-ex3-set1', targetReps: 'Match play (~90 min)' }],
      },
      {
        id: 'sat-ex4', name: 'Cool-Down Jog/Walk', targetWeight: 'bodyweight', isActivity: true,
        description: 'Light jogging or walking to gradually lower heart rate and aid recovery after the match.',
        videoUrl: 'https://www.youtube.com/embed/placeholder',
        muscleGroups: ['Full Body', 'Cardio'],
        sets: [{ id: 'sat-ex4-set1', targetReps: '10 min easy' }],
      },
      {
        id: 'sat-ex5', name: 'Static Stretch', isStretch: true, isActivity: true, targetWeight: 'N/A',
        description: 'Holding stretches for major muscle groups used during the match to improve flexibility and aid recovery.',
        videoUrl: 'https://www.youtube.com/embed/Sj_N63D0Zck',
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
    mapsToActualDayOfWeek: 0,
    exercises: [
      {
        id: 'sun-ex1', name: 'Walking', isRecovery: true, isActivity: true, targetWeight: 'bodyweight',
        description: 'Low-intensity walking to promote blood flow and recovery without stressing the body.',
        videoUrl: 'https://www.youtube.com/embed/placeholder',
        muscleGroups: ['Full Body', 'Cardio'],
        sets: [{ id: 'sun-ex1-set1', targetReps: '1 hour, 10,000 Steps' }],
      },
      {
        id: 'sun-ex2', name: 'Foam-Roll Quads', targetWeight: 'bodyweight', isFoamRoll: true, isRecovery: true,
        description: 'Using a foam roller to massage and release tension in the quadriceps muscles.',
        videoUrl: 'https://www.youtube.com/embed/fSHS_rQ02nc',
        muscleGroups: ['Quads'],
        sets: [{ id: 'sun-ex2-set1', targetReps: '2 min' }],
      },
      {
        id: 'sun-ex3', name: 'Foam-Roll Hamstrings', targetWeight: 'bodyweight', isFoamRoll: true, isRecovery: true,
        description: 'Using a foam roller to massage and release tension in the hamstring muscles.',
        videoUrl: 'https://www.youtube.com/embed/HRxVHeE_23c',
        muscleGroups: ['Hamstrings'],
        sets: [{ id: 'sun-ex3-set1', targetReps: '2 min' }],
      },
      {
        id: 'sun-ex4', name: 'Foam-Roll Lats', targetWeight: 'bodyweight', isFoamRoll: true, isRecovery: true,
        description: 'Using a foam roller to massage and release tension in the latissimus dorsi muscles.',
        videoUrl: 'https://www.youtube.com/embed/j9a3sC4H8Q0',
        muscleGroups: ['Lats'],
        sets: [{ id: 'sun-ex4-set1', targetReps: '2 min' }],
      },
      {
        id: 'sun-ex5', name: 'PNF Hamstring Stretch', isStretch: true, isRecovery: true, targetWeight: 'N/A',
        description: 'Proprioceptive Neuromuscular Facilitation (PNF) stretching for hamstrings, often involving a contract-relax sequence.',
        videoUrl: 'https://www.youtube.com/embed/HvzCHEPYi_M',
        muscleGroups: ['Hamstrings'],
        sets: [{ id: 'sun-ex5-set1', targetReps: '2 × 30 s ea leg' }],
      },
      {
        id: 'sun-ex6', name: 'PNF Hip-Flexor Stretch', isStretch: true, isRecovery: true, targetWeight: 'N/A',
        description: 'PNF stretching for hip flexor muscles.',
        videoUrl: 'https://www.youtube.com/embed/Vdx4fyH00pc',
        muscleGroups: ['Hip Flexors', 'Quads'],
        sets: [{ id: 'sun-ex6-set1', targetReps: '2 × 30 s ea side' }],
      },
      {
        id: 'sun-ex7', name: 'Shoulder Dislocates', targetWeight: 'band', isStretch: true, isRecovery: true,
        description: 'A shoulder mobility exercise using a band or stick, involving a wide circular motion of the arms.',
        videoUrl: 'https://www.youtube.com/embed/1QE3y_C2YFA',
        muscleGroups: ['Shoulders', 'Chest'],
        sets: [{ id: 'sun-ex7-set1', targetReps: '15 reps' }],
      },
    ],
  },
];

export const calisthenicsBeastPlan: WeeklyPlan = [
  {
    id: 'cal-monday',
    dayName: 'Monday',
    title: 'Upper Body Strength & Skill (Pull & Core)',
    mapsToActualDayOfWeek: 1,
    notes: 'Warm-up thoroughly. Focus on form for all exercises.',
    exercises: [
      {
        id: 'cal-mon-skill-hs', name: 'Skill: Handstand Practice', isSkill: true, unit: 's',
        description: 'Use wall for support if needed. Focus on stacking joints, controlled breathing. If comfortable, practice free handstand attempts.',
        videoUrl: 'https://www.youtube.com/embed/xsk6P93s5ww', muscleGroups: ['Shoulders', 'Core', 'Triceps', 'Traps'],
        sets: [
          { id: 'cal-mon-skill-hs-s1', targetReps: '30-60', unit: 's' },
          { id: 'cal-mon-skill-hs-s2', targetReps: '30-60', unit: 's' },
          { id: 'cal-mon-skill-hs-s3', targetReps: '30-60', unit: 's' },
        ],
      },
      {
        id: 'cal-mon-pullups-weighted', name: 'Weighted Pull-Ups / Lat Pulldown', unit: 'reps',
        targetWeight: 'Bodyweight / Add 2.5-10 kg / Lat Pulldown 80% BW',
        description: 'Use weight belt/dumbbell or Lat Pulldown machine for assistance/regression. Slow, controlled reps.',
        videoUrl: 'https://www.youtube.com/embed/huR4B2aDhKk', muscleGroups: ['Lats', 'Biceps', 'Upper Back'],
        sets: [
          { id: 'cal-mon-pullups-w-s1', targetReps: '5-8' },
          { id: 'cal-mon-pullups-w-s2', targetReps: '5-8' },
          { id: 'cal-mon-pullups-w-s3', targetReps: '5-8' },
          { id: 'cal-mon-pullups-w-s4', targetReps: '5-8' },
        ],
      },
      {
        id: 'cal-mon-archer-pullups', name: 'Archer Pull-Ups / Wide Pull-Ups', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'Perform Archer Pull-Ups, focusing on shifting weight to one arm, or Wide Pull-Ups for broader lat engagement.',
        videoUrl: 'https://www.youtube.com/embed/IWj7JgD0gB8', muscleGroups: ['Lats', 'Biceps', 'Shoulders'],
        sets: [
          { id: 'cal-mon-archer-s1', targetReps: '4-6 (each side for Archer)' },
          { id: 'cal-mon-archer-s2', targetReps: '4-6 (each side for Archer)' },
          { id: 'cal-mon-archer-s3', targetReps: '4-6 (each side for Archer)' },
        ],
      },
      {
        id: 'cal-mon-inverted-rows', name: 'Australian Pull-Ups (Inverted Rows)', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'Use Smith Machine bar or low bar in power cage. Adjust bar height to change difficulty.',
        videoUrl: 'https://www.youtube.com/embed/D7jvi0tN84U', muscleGroups: ['Upper Back', 'Biceps', 'Lats'],
        sets: [
          { id: 'cal-mon-invrow-s1', targetReps: '10-15' },
          { id: 'cal-mon-invrow-s2', targetReps: '10-15' },
          { id: 'cal-mon-invrow-s3', targetReps: '10-15' },
        ],
      },
      {
        id: 'cal-mon-lsit', name: 'L-Sit Holds', targetWeight: 'Bodyweight', isCore: true, unit: 's',
        description: 'Use parallel bars, dip station, or floor. Aim for straight legs and 90-degree angle.',
        videoUrl: 'https://www.youtube.com/embed/PzAmVcjY2X8', muscleGroups: ['Core', 'Hip Flexors', 'Triceps', 'Shoulders'],
        sets: [
          { id: 'cal-mon-lsit-s1', targetReps: '10-20', unit: 's' },
          { id: 'cal-mon-lsit-s2', targetReps: '10-20', unit: 's' },
          { id: 'cal-mon-lsit-s3', targetReps: '10-20', unit: 's' },
        ],
      },
      {
        id: 'cal-mon-hanging-leg-raises', name: 'Hanging Leg Raises / Toes to Bar', targetWeight: 'Bodyweight', isCore: true, unit: 'reps',
        description: 'Hang from a pull-up bar. Raise legs straight up (or knees for regression) towards the bar.',
        videoUrl: 'https://www.youtube.com/embed/1A0Sqg_M39k', muscleGroups: ['Abs (Lower)', 'Hip Flexors', 'Core'],
        sets: [
          { id: 'cal-mon-hlr-s1', targetReps: '10-15' },
          { id: 'cal-mon-hlr-s2', targetReps: '10-15' },
          { id: 'cal-mon-hlr-s3', targetReps: '10-15' },
        ],
      },
      {
        id: 'cal-mon-plank', name: 'Core – Plank', targetWeight: 'Bodyweight', unit: 's', isCore: true,
        description: 'Maintain a straight line from head to heels, engaging the core. Avoid letting hips sag.',
        videoUrl: 'https://www.youtube.com/embed/ASdvN_XEl_c', muscleGroups: ['Core', 'Abs', 'Obliques', 'Lower Back'],
        sets: [
          { id: 'cal-mon-plank-s1', targetReps: '60-90', unit: 's' },
          { id: 'cal-mon-plank-s2', targetReps: '60-90', unit: 's' },
          { id: 'cal-mon-plank-s3', targetReps: 'to failure', unit: 's' },
        ],
      },
    ],
  },
  {
    id: 'cal-tuesday',
    dayName: 'Tuesday',
    title: 'Lower Body & Active Mobility',
    mapsToActualDayOfWeek: 2,
    exercises: [
      {
        id: 'cal-tue-pistol-squats', name: 'Pistol Squats (Assisted if needed)', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'Single-leg squat. Use TRX, rack, or stable object for support if needed to maintain balance and depth.',
        videoUrl: 'https://www.youtube.com/embed/vq5-vdgJc0I', muscleGroups: ['Quads', 'Glutes', 'Hamstrings', 'Core', 'Balance'],
        sets: [
          { id: 'cal-tue-pistol-s1', targetReps: '5-8 (each leg)' },
          { id: 'cal-tue-pistol-s2', targetReps: '5-8 (each leg)' },
          { id: 'cal-tue-pistol-s3', targetReps: '5-8 (each leg)' },
        ],
      },
      {
        id: 'cal-tue-bulgarian-split-squats', name: 'Bulgarian Split Squats', targetWeight: 'Bodyweight (or add DBs)', unit: 'reps',
        description: 'Rear foot elevated on a bench or plyo box. Focus on controlled descent and driving up through the front heel.',
        videoUrl: 'https://www.youtube.com/embed/2C-uNgKwPLE', muscleGroups: ['Quads', 'Glutes', 'Hamstrings'],
        sets: [
          { id: 'cal-tue-bss-s1', targetReps: '10-12 (each leg)' },
          { id: 'cal-tue-bss-s2', targetReps: '10-12 (each leg)' },
          { id: 'cal-tue-bss-s3', targetReps: '10-12 (each leg)' },
        ],
      },
      {
        id: 'cal-tue-glute-bridges', name: 'Glute Bridges / Single Leg Glute Bridges', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'Lie on your back, knees bent, feet flat. Lift hips towards the ceiling, squeezing glutes. Progress to single leg.',
        videoUrl: 'https://www.youtube.com/embed/8bbE64Nu_2U', muscleGroups: ['Glutes', 'Hamstrings', 'Core'],
        sets: [
          { id: 'cal-tue-gb-s1', targetReps: '15-20' },
          { id: 'cal-tue-gb-s2', targetReps: '15-20' },
          { id: 'cal-tue-gb-s3', targetReps: '15-20' },
        ],
      },
      {
        id: 'cal-tue-calf-raises', name: 'Calf Raises (Bodyweight or Smith Machine)', targetWeight: 'Bodyweight / Add light weight', unit: 'reps',
        description: 'Stand with balls of feet on an elevated surface (optional). Raise heels as high as possible, then lower slowly.',
        videoUrl: 'https://www.youtube.com/embed/JbyjNymZOt0', muscleGroups: ['Calves'],
        sets: [
          { id: 'cal-tue-cr-s1', targetReps: '25-30' },
          { id: 'cal-tue-cr-s2', targetReps: '25-30' },
          { id: 'cal-tue-cr-s3', targetReps: '25-30' },
        ],
      },
      {
        id: 'cal-tue-mobility-circuit', name: 'Mobility Circuit', isMobility: true, unit: 's',
        description: 'Perform 2-3 rounds, 30-45s per exercise. Focus on range of motion and breathing.',
        videoUrl: 'https://www.youtube.com/embed/L_xrDAtykMI', // General mobility routine
        muscleGroups: ['Full Body', 'Flexibility'],
        sets: [
          { id: 'cal-tue-mob-s1', targetReps: '30-45s/side', notes: 'Couch Stretch' },
          { id: 'cal-tue-mob-s2', targetReps: '30-45s/side', notes: 'Pigeon Stretch' },
          { id: 'cal-tue-mob-s3', targetReps: '30-45s/side', notes: 'Hip Flexor Stretch' },
          { id: 'cal-tue-mob-s4', targetReps: '30-45', notes: 'Cat-Cow' },
          { id: 'cal-tue-mob-s5', targetReps: '30-45', notes: 'Thoracic Spine Rotations' },
        ],
        notes: 'Repeat circuit 2-3 times'
      },
    ],
  },
   {
    id: 'cal-wednesday',
    dayName: 'Wednesday',
    title: 'Upper Body Strength & Skill (Push & Core)',
    mapsToActualDayOfWeek: 3,
    exercises: [
      {
        id: 'cal-wed-skill-planche', name: 'Skill: Leaning Forward Push-ups / Pseudo Planche Push-ups', isSkill: true, targetWeight: 'Bodyweight', unit: 'reps',
        description: 'Focus on leaning forward as much as possible, engaging core. Can be done on floor or parallel bars for wrist comfort.',
        videoUrl: 'https://www.youtube.com/embed/hHXW1q4iJ08', muscleGroups: ['Shoulders (Front)', 'Chest', 'Triceps', 'Core'],
        sets: [
          { id: 'cal-wed-skill-planche-s1', targetReps: '5-8' },
          { id: 'cal-wed-skill-planche-s2', targetReps: '5-8' },
          { id: 'cal-wed-skill-planche-s3', targetReps: '5-8' },
        ],
      },
      {
        id: 'cal-wed-dips-weighted', name: 'Weighted Dips / Assisted Dips', unit: 'reps',
        targetWeight: 'Bodyweight / Add 2.5-10 kg / Use assisted dip machine',
        description: 'Use weight belt/dumbbell or Dip Machine for assistance/regression. Controlled descent, full range of motion.',
        videoUrl: 'https://www.youtube.com/embed/2z8JmcrW-As', muscleGroups: ['Triceps', 'Chest (Lower)', 'Shoulders (Front)'],
        sets: [
          { id: 'cal-wed-dips-w-s1', targetReps: '8-12' },
          { id: 'cal-wed-dips-w-s2', targetReps: '8-12' },
          { id: 'cal-wed-dips-w-s3', targetReps: '8-12' },
          { id: 'cal-wed-dips-w-s4', targetReps: '8-12' },
        ],
      },
      {
        id: 'cal-wed-decline-pushups', name: 'Decline Push-Ups', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'Feet elevated on a bench or plyo box to target upper chest and shoulders more intensely.',
        videoUrl: 'https://www.youtube.com/embed/Pkj8LLRsoDw', muscleGroups: ['Chest (Upper)', 'Shoulders (Front)', 'Triceps'],
        sets: [
          { id: 'cal-wed-decline-s1', targetReps: '12-15' },
          { id: 'cal-wed-decline-s2', targetReps: '12-15' },
          { id: 'cal-wed-decline-s3', targetReps: '12-15' },
        ],
      },
      {
        id: 'cal-wed-pike-hspu', name: 'Pike Push-Ups / Wall Handstand Push-Ups', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'Pike push-ups with feet on floor or elevated for progression. Or, Wall Handstand Push-Ups (facing wall or back to wall).',
        videoUrl: 'https://www.youtube.com/embed/sposKfusNqA', muscleGroups: ['Shoulders', 'Triceps', 'Traps'],
        sets: [
          { id: 'cal-wed-pike-s1', targetReps: '8-12' },
          { id: 'cal-wed-pike-s2', targetReps: '8-12' },
          { id: 'cal-wed-pike-s3', targetReps: '8-12' },
        ],
      },
      {
        id: 'cal-wed-triceps-ext', name: 'Bodyweight Triceps Extensions', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'E.g., Triceps extensions on parallel bars/rings (if available), or close-grip push-ups with elbows tucked.',
        videoUrl: 'https://www.youtube.com/embed/h3g3x1q4R3A', // Example: Triceps extension on bar
        muscleGroups: ['Triceps'],
        sets: [
          { id: 'cal-wed-tricep-s1', targetReps: '10-15' },
          { id: 'cal-wed-tricep-s2', targetReps: '10-15' },
          { id: 'cal-wed-tricep-s3', targetReps: '10-15' },
        ],
      },
      {
        id: 'cal-wed-dragon-flags', name: 'Dragon Flags / Reverse Crunches', targetWeight: 'Bodyweight', isCore: true, unit: 'reps',
        description: 'Use sturdy bench or decline bench. Dragon flags for advanced core strength, reverse crunches for regression.',
        videoUrl: 'https://www.youtube.com/embed/moyh9_hIIA0', muscleGroups: ['Abs', 'Core', 'Obliques'],
        sets: [
          { id: 'cal-wed-dragon-s1', targetReps: '8-12' },
          { id: 'cal-wed-dragon-s2', targetReps: '8-12' },
          { id: 'cal-wed-dragon-s3', targetReps: '8-12' },
        ],
      },
      {
        id: 'cal-wed-side-plank', name: 'Core – Side Plank', targetWeight: 'Bodyweight', unit: 's', isCore: true,
        description: 'Maintain a straight line from head to feet, supporting body on one forearm/hand. Engage obliques.',
        videoUrl: 'https://www.youtube.com/embed/1h4g9sQxV0A', muscleGroups: ['Obliques', 'Core', 'Abs'],
        sets: [
          { id: 'cal-wed-sideplank-s1', targetReps: '45-60 (each side)', unit: 's' },
          { id: 'cal-wed-sideplank-s2', targetReps: '45-60 (each side)', unit: 's' },
          { id: 'cal-wed-sideplank-s3', targetReps: '45-60 (each side)', unit: 's' },
        ],
      },
    ],
  },
  {
    id: 'cal-thursday',
    dayName: 'Thursday',
    title: 'Active Recovery / Light Cardio & Mobility',
    mapsToActualDayOfWeek: 4,
    isRecovery: true,
    exercises: [
      {
        id: 'cal-thu-cardio', name: 'Light Cardio', isActivity: true, unit: 'min',
        description: 'Choose preference: Treadmill (jogging/brisk walking), Elliptical, Stationary Bike.',
        videoUrl: 'https://www.youtube.com/embed/placeholder', muscleGroups: ['Cardio', 'Full Body'],
        sets: [{ id: 'cal-thu-cardio-s1', targetReps: '30-45', unit: 'min', notes: 'Light to moderate intensity' }],
      },
      {
        id: 'cal-thu-foam-roll', name: 'Foam Rolling', isFoamRoll: true, isMobility: true, unit: 'min',
        description: 'Use gym\'s foam rollers. Focus on Quads, Hamstrings, Glutes, Lats, Chest, Shoulders.',
        videoUrl: 'https://www.youtube.com/embed/fTvZ47nN3XU', // Full body foam roll
        muscleGroups: ['Full Body'],
        sets: [{ id: 'cal-thu-foam-s1', targetReps: '2-3 min per muscle group' }],
      },
      {
        id: 'cal-thu-static-stretch', name: 'Static Stretching', isStretch: true, isMobility: true, unit: 's',
        description: 'Hold each static stretch for 30 seconds, 2-3 times. Focus on major muscle groups.',
        videoUrl: 'https://www.youtube.com/embed/Sj_N63D0Zck', // Full body static stretch
        muscleGroups: ['Full Body', 'Flexibility'],
        sets: [{ id: 'cal-thu-stretch-s1', targetReps: '30s per stretch, 2-3x' }],
      },
      {
        id: 'cal-thu-joint-rotations', name: 'Joint Rotations & Mobility Drills', isMobility: true, unit: 'min',
        description: 'Ankle rotations, hip circles, arm circles, wrist stretches.',
        videoUrl: 'https://www.youtube.com/embed/83hWIc0997g', // Joint mobility routine
        muscleGroups: ['Joints', 'Full Body'],
        sets: [{ id: 'cal-thu-joint-s1', targetReps: '5-10 min total' }],
      },
    ],
  },
  {
    id: 'cal-friday',
    dayName: 'Friday',
    title: 'Full Body Calisthenics Circuit (Endurance)',
    mapsToActualDayOfWeek: 5,
    notes: 'Perform as a circuit, minimal rest between exercises; 1-2 min rest between rounds. 3-4 rounds total.',
    isConditioning: true,
    exercises: [
      {
        id: 'cal-fri-pullups', name: 'Pull-Ups', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'Use pull-up bar.', videoUrl: 'https://www.youtube.com/embed/eGo4IYlbE5g', muscleGroups: ['Lats', 'Biceps'],
        sets: [{ id: 'cal-fri-pullups-s1', targetReps: 'Max (target 8-12)' }],
      },
      {
        id: 'cal-fri-pushups', name: 'Push-Ups', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'On floor or with push-up handles for wrist comfort.', videoUrl: 'https://www.youtube.com/embed/IODxDxX7oi4', muscleGroups: ['Chest', 'Triceps', 'Shoulders'],
        sets: [{ id: 'cal-fri-pushups-s1', targetReps: 'Max (target 15-25)' }],
      },
      {
        id: 'cal-fri-squats', name: 'Bodyweight Squats / Jump Squats', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'On gym floor. Jump squats for added intensity.', videoUrl: 'https://www.youtube.com/embed/U4s4mEQ5VqU', muscleGroups: ['Quads', 'Glutes', 'Hamstrings'],
        sets: [{ id: 'cal-fri-squats-s1', targetReps: '15-20' }],
      },
      {
        id: 'cal-fri-dips', name: 'Dips', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'Use dip station or parallel bars.', videoUrl: 'https://www.youtube.com/embed/2z8JmcrW-As', muscleGroups: ['Triceps', 'Chest', 'Shoulders'],
        sets: [{ id: 'cal-fri-dips-s1', targetReps: 'Max (target 10-15)' }],
      },
      {
        id: 'cal-fri-inverted-rows', name: 'Inverted Rows', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'Use Smith Machine bar or low bar in power cage.', videoUrl: 'https://www.youtube.com/embed/D7jvi0tN84U', muscleGroups: ['Upper Back', 'Biceps'],
        sets: [{ id: 'cal-fri-invrow-s1', targetReps: '12-18' }],
      },
      {
        id: 'cal-fri-burpees', name: 'Burpees', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'On gym floor. Full body explosive movement.', videoUrl: 'https://www.youtube.com/embed/JZQA08SlJnM', muscleGroups: ['Full Body', 'Cardio'],
        sets: [{ id: 'cal-fri-burpees-s1', targetReps: '10-15' }],
      },
      {
        id: 'cal-fri-plank', name: 'Plank', targetWeight: 'Bodyweight', unit: 's', isCore: true,
        description: 'Hold with good form.', videoUrl: 'https://www.youtube.com/embed/ASdvN_XEl_c', muscleGroups: ['Core', 'Abs'],
        sets: [{ id: 'cal-fri-plank-s1', targetReps: '45-60', unit: 's' }],
      },
    ],
  },
  {
    id: 'cal-saturday',
    dayName: 'Saturday',
    title: 'Skill Development & Outdoor / Active Recreation',
    mapsToActualDayOfWeek: 6,
    exercises: [
      {
        id: 'cal-sat-skill-focus', name: 'Focused Skill Practice', isSkill: true, unit: 's',
        description: 'Choose 1-2 skills (e.g., Front Lever, Planche, advanced Handstand). Use gym equipment like power rack, parallettes, wall. Work on progressions for 20-30 min, focusing on form and short, intense efforts.',
        videoUrl: 'https://www.youtube.com/embed/placeholder', // User specific
        muscleGroups: ['Skill-Dependent'],
        sets: [
          { id: 'cal-sat-skill-flt', targetReps: 'max hold (5-10s)', notes: 'Front Lever Tucks: 3-5 sets' },
          { id: 'cal-sat-skill-pll', targetReps: 'max hold (5-10s)', notes: 'Planche Leans: 3-5 sets' },
          { id: 'cal-sat-skill-hsh', targetReps: 'max hold (20-40s)', notes: 'Handstand Holds: 3-5 sets' },
        ],
        notes: 'Choose 1-2 skills to focus on.'
      },
      {
        id: 'cal-sat-outdoor-activity', name: 'Outdoor Activity / Active Recreation', isActivity: true, unit: 'min',
        description: 'Hiking, cycling, swimming, playing a sport, or just a long walk.',
        videoUrl: 'https://www.youtube.com/embed/placeholder', muscleGroups: ['Full Body', 'Cardio'],
        sets: [{ id: 'cal-sat-outdoor-s1', targetReps: '60-90 min', unit: 'min', notes: 'Enjoyable, moderate intensity' }],
      },
    ],
  },
  {
    id: 'cal-sunday',
    dayName: 'Sunday',
    title: 'Complete Rest',
    mapsToActualDayOfWeek: 0,
    isRecovery: true,
    notes: 'Allow your body to fully recover. Focus on good nutrition and hydration.',
    exercises: [
      {
        id: 'cal-sun-rest', name: 'Rest Day', isActivity: true,
        description: 'Focus on recovery, nutrition, and hydration. Light stretching if desired.',
        videoUrl: 'https://www.youtube.com/embed/placeholder', muscleGroups: ['N/A'],
        sets: [{ id: 'cal-sun-rest-s1', targetReps: 'Full day' }],
      },
    ],
  },
];

// The existing exercise library
export const exerciseLibrary: WeeklyPlan = [{
    id: 'exercise-library',
    dayName: 'Exercise Library',
    title: 'Reference Exercises (Not a Workout Day)',
    notes: 'This section contains additional exercises for autocomplete and reference. It is not intended as a structured workout.',
    exercises: [
      {
        id: 'lib-bp', name: 'Barbell Bench Press', targetWeight: '60 kg', unit: 'reps',
        description: 'Compound exercise targeting chest, shoulders, and triceps. Lie on a bench, lower a barbell to the chest, and press it back up.',
        videoUrl: 'https://www.youtube.com/embed/rT7DgCr-3pg',
        muscleGroups: ['Chest', 'Triceps', 'Shoulders (Front)'],
        sets: [{ id: 'lib-bp-s1', targetReps: '8-12' }, { id: 'lib-bp-s2', targetReps: '8-12' }, { id: 'lib-bp-s3', targetReps: '8-12' }],
      },
      {
        id: 'lib-dl', name: 'Deadlift (Conventional)', targetWeight: '100 kg', unit: 'reps',
        description: 'Compound full-body exercise. Lift a loaded barbell off the floor to a standing position, keeping the back straight.',
        videoUrl: 'https://www.youtube.com/embed/ytGaGIn3SjE',
        muscleGroups: ['Hamstrings', 'Glutes', 'Lower Back', 'Traps', 'Quads', 'Forearms'],
        sets: [{ id: 'lib-dl-s1', targetReps: '5' }, { id: 'lib-dl-s2', targetReps: '5' }, { id: 'lib-dl-s3', targetReps: '5' }],
      },
      {
        id: 'lib-ohp', name: 'Overhead Press (Barbell)', targetWeight: '40 kg', unit: 'reps',
        description: 'Compound shoulder exercise. Press a barbell from the front of the shoulders overhead to full lockout.',
        videoUrl: 'https://www.youtube.com/embed/2yjwXTZQDDI',
        muscleGroups: ['Shoulders (All Heads)', 'Triceps', 'Upper Chest'],
        sets: [{ id: 'lib-ohp-s1', targetReps: '8-12' }, { id: 'lib-ohp-s2', targetReps: '8-12' }, { id: 'lib-ohp-s3', targetReps: '8-12' }],
      },
      {
        id: 'lib-bicep-curl-db', name: 'Dumbbell Bicep Curl', targetWeight: '12 kg', unit: 'reps',
        description: 'Isolation exercise for biceps. Curl dumbbells up towards shoulders, keeping elbows stable.',
        videoUrl: 'https://www.youtube.com/embed/ykJmrZ5v0Oo',
        muscleGroups: ['Biceps'],
        sets: [{ id: 'lib-bc-db-s1', targetReps: '10-15' }, { id: 'lib-bc-db-s2', targetReps: '10-15' }, { id: 'lib-bc-db-s3', targetReps: '10-15' }],
      },
      {
        id: 'lib-tri-pushdown', name: 'Triceps Cable Pushdown (Bar)', targetWeight: '20 kg', unit: 'reps',
        description: 'Isolation exercise for triceps. Push a bar attachment down on a cable machine until arms are fully extended.',
        videoUrl: 'https://www.youtube.com/embed/2-LAMcpzODU',
        muscleGroups: ['Triceps'],
        sets: [{ id: 'lib-tp-s1', targetReps: '10-15' }, { id: 'lib-tp-s2', targetReps: '10-15' }, { id: 'lib-tp-s3', targetReps: '10-15' }],
      },
       {
        id: 'lib-lunge-db', name: 'Dumbbell Lunges', targetWeight: '10 kg each hand', unit: 'reps',
        description: 'Unilateral leg exercise targeting quads, glutes, and hamstrings. Step forward and lower hips until both knees are bent at 90 degrees.',
        videoUrl: 'https://www.youtube.com/embed/D7KaRcUTQeE',
        muscleGroups: ['Quads', 'Glutes', 'Hamstrings'],
        sets: [{ id: 'lib-lunge-s1', targetReps: '10-12 per leg' }, { id: 'lib-lunge-s2', targetReps: '10-12 per leg' }, { id: 'lib-lunge-s3', targetReps: '10-12 per leg' }],
      },
      {
        id: 'lib-crunch', name: 'Crunches', targetWeight: 'Bodyweight', unit: 'reps', isCore: true,
        description: 'Abdominal exercise. Lie on your back, knees bent, and lift your upper body towards your knees.',
        videoUrl: 'https://www.youtube.com/embed/Xyd_fa5zoEU',
        muscleGroups: ['Abs (Upper)'],
        sets: [{ id: 'lib-crunch-s1', targetReps: '15-20' }, { id: 'lib-crunch-s2', targetReps: '15-20' }, { id: 'lib-crunch-s3', targetReps: '15-20' }],
      },
      {
        id: 'lib-good-morning', name: 'Good Mornings', targetWeight: 'Barbell (light)', unit: 'reps',
        description: 'Hinge movement targeting hamstrings and lower back. With a barbell on shoulders, hinge at hips keeping legs mostly straight.',
        videoUrl: 'https://www.youtube.com/embed/vKPGe8zb2T4',
        muscleGroups: ['Hamstrings', 'Glutes', 'Lower Back'],
        sets: [{ id: 'lib-gm-s1', targetReps: '12-15' }, { id: 'lib-gm-s2', targetReps: '12-15' }],
      },
      {
        id: 'lib-hyperext', name: 'Hyperextensions (Back Extensions)', targetWeight: 'Bodyweight or Plate', unit: 'reps',
        description: 'Targets lower back, glutes, and hamstrings. Performed on a hyperextension bench.',
        videoUrl: 'https://www.youtube.com/embed/ph3pddY_vAw',
        muscleGroups: ['Lower Back', 'Glutes', 'Hamstrings'],
        sets: [{ id: 'lib-hyper-s1', targetReps: '12-15' }, { id: 'lib-hyper-s2', targetReps: '12-15' }, { id: 'lib-hyper-s3', targetReps: '12-15' }],
      },
      {
        id: 'lib-kettlebell-swing', name: 'Kettlebell Swing (Russian)', targetWeight: '16 kg', unit: 'reps',
        description: 'Explosive hip hinge movement with a kettlebell, targeting glutes, hamstrings, and core.',
        videoUrl: 'https://www.youtube.com/embed/YSxHifyI6s8',
        muscleGroups: ['Glutes', 'Hamstrings', 'Lower Back', 'Core', 'Shoulders'],
        sets: [{ id: 'lib-kb-swing-s1', targetReps: '15-20' }, { id: 'lib-kb-swing-s2', targetReps: '15-20' }, { id: 'lib-kb-swing-s3', targetReps: '15-20' }],
      },
      {
        id: 'lib-goblet-squat', name: 'Goblet Squat', targetWeight: '20 kg Dumbbell', unit: 'reps',
        description: 'Squat variation holding a dumbbell or kettlebell at chest level. Good for learning squat form.',
        videoUrl: 'https://www.youtube.com/embed/MeW1bB741zY',
        muscleGroups: ['Quads', 'Glutes', 'Core'],
        sets: [{ id: 'lib-goblet-s1', targetReps: '10-15' }, { id: 'lib-goblet-s2', targetReps: '10-15' }, { id: 'lib-goblet-s3', targetReps: '10-15' }],
      },
      {
        id: 'lib-farmers-walk', name: "Farmer's Walk", targetWeight: 'Heavy Dumbbells/Kettlebells', unit: 's',
        description: 'Carry heavy weights in each hand and walk for distance or time. Builds grip strength, core stability, and overall toughness.',
        videoUrl: 'https://www.youtube.com/embed/6ENGW93H1vM',
        muscleGroups: ['Forearms', 'Traps', 'Core', 'Legs'],
        sets: [{ id: 'lib-fw-s1', targetReps: '30-60', unit: 's' }, { id: 'lib-fw-s2', targetReps: '30-60', unit: 's' }],
      },
      {
        id: 'lib-box-jump', name: 'Box Jumps', targetWeight: 'Bodyweight', unit: 'reps', isConditioning: true,
        description: 'Plyometric exercise involving jumping onto a sturdy box. Develops explosive power.',
        videoUrl: 'https://www.youtube.com/embed/RXD309N5388',
        muscleGroups: ['Quads', 'Glutes', 'Hamstrings', 'Calves'],
        sets: [{ id: 'lib-bj-s1', targetReps: '8-10' }, { id: 'lib-bj-s2', targetReps: '8-10' }, { id: 'lib-bj-s3', targetReps: '8-10' }],
      },
      {
        id: 'lib-burpee', name: 'Burpees', targetWeight: 'Bodyweight', unit: 'reps', isConditioning: true,
        description: 'Full-body exercise combining a squat, push-up, and jump. Excellent for conditioning.',
        videoUrl: 'https://www.youtube.com/embed/JZQA08SlJnM',
        muscleGroups: ['Full Body', 'Cardio'],
        sets: [{ id: 'lib-burpee-s1', targetReps: '10-15' }, { id: 'lib-burpee-s2', targetReps: '10-15' }],
      },
      {
        id: 'lib-mountain-climber', name: 'Mountain Climbers', targetWeight: 'Bodyweight', unit: 'reps', isCore: true, isConditioning: true,
        description: 'Dynamic core exercise mimicking climbing. Start in a plank, bring one knee to chest, then alternate quickly.',
        videoUrl: 'https://www.youtube.com/embed/nmwgirgXLYM',
        muscleGroups: ['Core', 'Shoulders', 'Cardio', 'Hip Flexors'],
        sets: [{ id: 'lib-mc-s1', targetReps: '20-30 per side' }, { id: 'lib-mc-s2', targetReps: '20-30 per side' }],
      },
      {
        id: 'lib-tbar-row', name: 'T-Bar Row', targetWeight: 'Plates', unit: 'reps',
        description: 'Compound back exercise using a T-bar machine or a barbell wedged into a corner. Pulls weight towards chest.',
        videoUrl: 'https://www.youtube.com/embed/KDEl3AmqB6I',
        muscleGroups: ['Lats', 'Rhomboids', 'Traps', 'Biceps'],
        sets: [{ id: 'lib-tbar-s1', targetReps: '8-12' }, { id: 'lib-tbar-s2', targetReps: '8-12' }, { id: 'lib-tbar-s3', targetReps: '8-12' }],
      },
      {
        id: 'lib-pendlay-row', name: 'Pendlay Row', targetWeight: 'Barbell', unit: 'reps',
        description: 'Strict barbell row where the bar rests on the floor between reps. Builds explosive pulling strength.',
        videoUrl: 'https://www.youtube.com/embed/ZlRrIsoN5xc',
        muscleGroups: ['Lats', 'Upper Back', 'Lower Back', 'Biceps'],
        sets: [{ id: 'lib-pendlay-s1', targetReps: '6-10' }, { id: 'lib-pendlay-s2', targetReps: '6-10' }, { id: 'lib-pendlay-s3', targetReps: '6-10' }],
      },
      {
        id: 'lib-skullcrusher', name: 'Skullcrushers (Lying Triceps Extension)', targetWeight: 'EZ Bar or Dumbbells', unit: 'reps',
        description: 'Triceps isolation exercise. Lying on a bench, lower weight towards forehead and extend back up.',
        videoUrl: 'https://www.youtube.com/embed/d_KZxkY_0cM',
        muscleGroups: ['Triceps'],
        sets: [{ id: 'lib-skull-s1', targetReps: '10-15' }, { id: 'lib-skull-s2', targetReps: '10-15' }, { id: 'lib-skull-s3', targetReps: '10-15' }],
      },
      {
        id: 'lib-close-grip-bp', name: 'Close Grip Bench Press', targetWeight: 'Barbell', unit: 'reps',
        description: 'Bench press variation with a narrower grip, emphasizing triceps development.',
        videoUrl: 'https://www.youtube.com/embed/cXbSJHT4i0I',
        muscleGroups: ['Triceps', 'Chest', 'Shoulders (Front)'],
        sets: [{ id: 'lib-cgbp-s1', targetReps: '8-12' }, { id: 'lib-cgbp-s2', targetReps: '8-12' }, { id: 'lib-cgbp-s3', targetReps: '8-12' }],
      },
      {
        id: 'lib-concentration-curl', name: 'Concentration Curl', targetWeight: 'Dumbbell', unit: 'reps',
        description: 'Bicep isolation exercise focusing on peak contraction. Seated, brace elbow against inner thigh and curl.',
        videoUrl: 'https://www.youtube.com/embed/Jvj2wV0vOYU',
        muscleGroups: ['Biceps'],
        sets: [{ id: 'lib-cc-s1', targetReps: '10-15 per arm' }, { id: 'lib-cc-s2', targetReps: '10-15 per arm' }],
      },
      {
        id: 'lib-hammer-curl', name: 'Hammer Curl', targetWeight: 'Dumbbells', unit: 'reps',
        description: 'Bicep curl variation with palms facing each other (neutral grip). Hits brachialis and brachioradialis.',
        videoUrl: 'https://www.youtube.com/embed/zC3nLlEvin4',
        muscleGroups: ['Biceps', 'Brachialis', 'Forearms'],
        sets: [{ id: 'lib-hc-s1', targetReps: '10-15' }, { id: 'lib-hc-s2', targetReps: '10-15' }, { id: 'lib-hc-s3', targetReps: '10-15' }],
      },
      {
        id: 'lib-shrugs', name: 'Barbell/Dumbbell Shrugs', targetWeight: 'Heavy', unit: 'reps',
        description: 'Isolation exercise for trapezius muscles. Hold weight and elevate shoulders towards ears.',
        videoUrl: 'https://www.youtube.com/embed/NAqCVe2mwzM',
        muscleGroups: ['Traps (Upper)'],
        sets: [{ id: 'lib-shrug-s1', targetReps: '12-20' }, { id: 'lib-shrug-s2', targetReps: '12-20' }, { id: 'lib-shrug-s3', targetReps: '12-20' }],
      },
      {
        id: 'lib-upright-row', name: 'Upright Row (Barbell/Dumbbell)', targetWeight: 'Moderate', unit: 'reps',
        description: 'Compound exercise for shoulders and traps. Pull weight vertically up towards chin, leading with elbows.',
        videoUrl: 'https://www.youtube.com/embed/ja33CSF15So',
        muscleGroups: ['Shoulders (Lateral, Front)', 'Traps'],
        sets: [{ id: 'lib-ur-s1', targetReps: '10-15' }, { id: 'lib-ur-s2', targetReps: '10-15' }, { id: 'lib-ur-s3', targetReps: '10-15' }],
      },
      {
        id: 'lib-arnold-press', name: 'Arnold Press', targetWeight: 'Dumbbells', unit: 'reps',
        description: 'Dumbbell shoulder press variation involving rotation to hit all three deltoid heads.',
        videoUrl: 'https://www.youtube.com/embed/3ml7oUxRBLQ',
        muscleGroups: ['Shoulders (All Heads)', 'Triceps'],
        sets: [{ id: 'lib-ap-s1', targetReps: '10-12' }, { id: 'lib-ap-s2', targetReps: '10-12' }, { id: 'lib-ap-s3', targetReps: '10-12' }],
      },
      {
        id: 'lib-pec-deck', name: 'Pec Deck Fly', targetWeight: 'Machine Stack', unit: 'reps',
        description: 'Chest isolation exercise on a pec deck machine. Squeeze arms together in front of chest.',
        videoUrl: 'https://www.youtube.com/embed/0ZT5jHXA08g',
        muscleGroups: ['Chest (Inner)'],
        sets: [{ id: 'lib-pd-s1', targetReps: '12-15' }, { id: 'lib-pd-s2', targetReps: '12-15' }, { id: 'lib-pd-s3', targetReps: '12-15' }],
      },
      {
        id: 'lib-cable-crossover', name: 'Cable Crossover', targetWeight: 'Cable Stack', unit: 'reps',
        description: 'Chest isolation exercise using cables. Bring handles together in front of body from various angles.',
        videoUrl: 'https://www.youtube.com/embed/taI4XduLpTk',
        muscleGroups: ['Chest'],
        sets: [{ id: 'lib-ccross-s1', targetReps: '12-15' }, { id: 'lib-ccross-s2', targetReps: '12-15' }, { id: 'lib-ccross-s3', targetReps: '12-15' }],
      },
      {
        id: 'lib-seated-calf-raise', name: 'Seated Calf Raise', targetWeight: 'Machine Stack/Plates', unit: 'reps',
        description: 'Calf exercise targeting the soleus muscle. Performed on a seated calf raise machine.',
        videoUrl: 'https://www.youtube.com/embed/JflgI0jZNtA',
        muscleGroups: ['Calves (Soleus)'],
        sets: [{ id: 'lib-scr-s1', targetReps: '15-25' }, { id: 'lib-scr-s2', targetReps: '15-25' }, { id: 'lib-scr-s3', targetReps: '15-25' }],
      },
      {
        id: 'lib-hack-squat', name: 'Hack Squat', targetWeight: 'Machine Plates', unit: 'reps',
        description: 'Machine-based squat variation that emphasizes quads. Body is supported by a sled.',
        videoUrl: 'https://www.youtube.com/embed/0tn5K9NlCfo',
        muscleGroups: ['Quads', 'Glutes'],
        sets: [{ id: 'lib-hs-s1', targetReps: '10-15' }, { id: 'lib-hs-s2', targetReps: '10-15' }, { id: 'lib-hs-s3', targetReps: '10-15' }],
      },
      {
        id: 'lib-front-squat', name: 'Front Squat', targetWeight: 'Barbell', unit: 'reps',
        description: 'Squat variation where barbell is held across front of shoulders. Emphasizes quads and core.',
        videoUrl: 'https://www.youtube.com/embed/m4ytaCJZpl0',
        muscleGroups: ['Quads', 'Glutes', 'Core', 'Upper Back'],
        sets: [{ id: 'lib-fs-s1', targetReps: '8-12' }, { id: 'lib-fs-s2', targetReps: '8-12' }, { id: 'lib-fs-s3', targetReps: '8-12' }],
      },
      {
        id: 'lib-bulgarian-split-squat', name: 'Bulgarian Split Squat', targetWeight: 'Dumbbells or Bodyweight', unit: 'reps',
        description: 'Unilateral squat variation with rear foot elevated. Targets quads, glutes, and improves balance.',
        videoUrl: 'https://www.youtube.com/embed/2C-uNgKwPLE',
        muscleGroups: ['Quads', 'Glutes', 'Hamstrings'],
        sets: [{ id: 'lib-bss-s1', targetReps: '10-12 per leg' }, { id: 'lib-bss-s2', targetReps: '10-12 per leg' }, { id: 'lib-bss-s3', targetReps: '10-12 per leg' }],
      },
      {
        id: 'lib-nordic-ham-curl', name: 'Nordic Hamstring Curl', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'Challenging eccentric hamstring exercise. Kneel, secure ankles, and slowly lower torso towards floor.',
        videoUrl: 'https://www.youtube.com/embed/d840OrGzVfM',
        muscleGroups: ['Hamstrings', 'Glutes'],
        sets: [{ id: 'lib-nhc-s1', targetReps: '3-6' }, { id: 'lib-nhc-s2', targetReps: '3-6' }, { id: 'lib-nhc-s3', targetReps: '3-6' }],
      },
      {
        id: 'lib-glute-ham-raise', name: 'Glute Ham Raise (GHR)', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'Exercise on GHR machine targeting hamstrings, glutes, and lower back.',
        videoUrl: 'https://www.youtube.com/embed/9G0u02A7d4g',
        muscleGroups: ['Hamstrings', 'Glutes', 'Lower Back'],
        sets: [{ id: 'lib-ghr-s1', targetReps: '8-12' }, { id: 'lib-ghr-s2', targetReps: '8-12' }, { id: 'lib-ghr-s3', targetReps: '8-12' }],
      },
      {
        id: 'lib-abductor-machine', name: 'Hip Abductor Machine', targetWeight: 'Machine Stack', unit: 'reps',
        description: 'Isolation exercise for outer thighs (hip abductors). Push legs outward against resistance.',
        videoUrl: 'https://www.youtube.com/embed/uOCpAce0yqM',
        muscleGroups: ['Hip Abductors', 'Glutes (Side)'],
        sets: [{ id: 'lib-abduct-s1', targetReps: '15-20' }, { id: 'lib-abduct-s2', targetReps: '15-20' }, { id: 'lib-abduct-s3', targetReps: '15-20' }],
      },
      {
        id: 'lib-adductor-machine', name: 'Hip Adductor Machine', targetWeight: 'Machine Stack', unit: 'reps',
        description: 'Isolation exercise for inner thighs (hip adductors). Squeeze legs inward against resistance.',
        videoUrl: 'https://www.youtube.com/embed/WDY2cO8444s',
        muscleGroups: ['Hip Adductors', 'Groin'],
        sets: [{ id: 'lib-adduct-s1', targetReps: '15-20' }, { id: 'lib-adduct-s2', targetReps: '15-20' }, { id: 'lib-adduct-s3', targetReps: '15-20' }],
      },
      {
        id: 'lib-cable-kickback', name: 'Cable Glute Kickback', targetWeight: 'Cable Stack', unit: 'reps',
        description: 'Glute isolation exercise using a cable machine and ankle strap. Kick leg back against resistance.',
        videoUrl: 'https://www.youtube.com/embed/tN2_AwgB12Y',
        muscleGroups: ['Glutes'],
        sets: [{ id: 'lib-ck-s1', targetReps: '15-20 per leg' }, { id: 'lib-ck-s2', targetReps: '15-20 per leg' }, { id: 'lib-ck-s3', targetReps: '15-20 per leg' }],
      },
      {
        id: 'lib-reverse-pec-deck', name: 'Reverse Pec Deck (Rear Delt Fly)', targetWeight: 'Machine Stack', unit: 'reps',
        description: 'Machine exercise targeting rear deltoids and upper back. Similar to dumbbell rear delt fly.',
        videoUrl: 'https://www.youtube.com/embed/4W40tB71zms',
        muscleGroups: ['Shoulders (Rear)', 'Rhomboids', 'Traps'],
        sets: [{ id: 'lib-rpd-s1', targetReps: '12-15' }, { id: 'lib-rpd-s2', targetReps: '12-15' }, { id: 'lib-rpd-s3', targetReps: '12-15' }],
      },
      {
        id: 'lib-superman', name: 'Superman', targetWeight: 'Bodyweight', unit: 'reps', isCore: true,
        description: 'Lower back and glute exercise. Lie prone, simultaneously lift arms, chest, and legs off floor.',
        videoUrl: 'https://www.youtube.com/embed/z6PJMT2y8GQ',
        muscleGroups: ['Lower Back', 'Glutes', 'Hamstrings'],
        sets: [{ id: 'lib-super-s1', targetReps: '15-20' }, { id: 'lib-super-s2', targetReps: '15-20' }],
      },
      {
        id: 'lib-bird-dog', name: 'Bird Dog', targetWeight: 'Bodyweight', unit: 'reps', isCore: true,
        description: 'Core stability exercise. From all fours, extend opposite arm and leg, maintaining a flat back.',
        videoUrl: 'https://www.youtube.com/embed/wiFNA3sqjCA',
        muscleGroups: ['Core', 'Glutes', 'Lower Back', 'Shoulders'],
        sets: [{ id: 'lib-bd-s1', targetReps: '10-12 per side' }, { id: 'lib-bd-s2', targetReps: '10-12 per side' }],
      }
    ],
  }];

// --- Optimized Gym & Calisthenics Blended Plan ---
const optimizedGymCalisthenicsPlan: WeeklyPlan = [
  {
    id: 'ogcb-day1',
    dayName: 'Monday',
    title: 'Upper Body - Push Focus',
    mapsToActualDayOfWeek: 1,
    notes: 'Warm-up: 5-10 min light cardio & dynamic stretches. Cool-down: 5-10 min static stretches.',
    exercises: [
      {
        id: 'ogcb-d1-ex1', name: 'Machine Chest Press', targetWeight: 'Moderate', unit: 'reps',
        description: 'Compound chest strength exercise using a machine press for stability and controlled movement.',
        videoUrl: 'https://www.youtube.com/embed/placeholder', muscleGroups: ['Chest', 'Shoulders', 'Triceps'],
        sets: [
          { id: 'ogcb-d1-ex1-s1', targetReps: '6-10' },
          { id: 'ogcb-d1-ex1-s2', targetReps: '6-10' },
          { id: 'ogcb-d1-ex1-s3', targetReps: '6-10' },
        ],
      },
      {
        id: 'ogcb-d1-ex2', name: 'Overhead Press (Barbell or Dumbbell)', targetWeight: 'Moderate', unit: 'reps',
        description: 'Compound shoulder strength exercise. Press weight overhead from shoulder level.',
        videoUrl: 'https://www.youtube.com/embed/2yjwXTZQDDI', muscleGroups: ['Shoulders', 'Triceps'],
        sets: [
          { id: 'ogcb-d1-ex2-s1', targetReps: '6-10' },
          { id: 'ogcb-d1-ex2-s2', targetReps: '6-10' },
          { id: 'ogcb-d1-ex2-s3', targetReps: '6-10' },
        ],
      },
      {
        id: 'ogcb-d1-ex3', name: 'Incline Dumbbell Press', targetWeight: 'Moderate', unit: 'reps',
        description: 'Targets upper chest, front deltoids, and triceps.',
        videoUrl: 'https://www.youtube.com/embed/8iPEnn-ltC8', muscleGroups: ['Chest (Upper)', 'Shoulders (Front)', 'Triceps'],
        sets: [
          { id: 'ogcb-d1-ex3-s1', targetReps: '8-12' },
          { id: 'ogcb-d1-ex3-s2', targetReps: '8-12' },
          { id: 'ogcb-d1-ex3-s3', targetReps: '8-12' },
        ],
      },
      {
        id: 'ogcb-d1-ex4', name: 'Dips (Parallel Bars or Assisted)', targetWeight: 'Bodyweight/Assisted', unit: 'reps',
        description: 'Calisthenics compound for triceps and lower chest.',
        videoUrl: 'https://www.youtube.com/embed/2z8JmcrW-As', muscleGroups: ['Triceps', 'Chest', 'Shoulders'],
        sets: [
          { id: 'ogcb-d1-ex4-s1', targetReps: '8-12' },
          { id: 'ogcb-d1-ex4-s2', targetReps: '8-12' },
          { id: 'ogcb-d1-ex4-s3', targetReps: '8-12' },
        ],
      },
      {
        id: 'ogcb-d1-ex5', name: 'Push-ups (Standard, Decline, or Pseudo Planche)', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'Progressive bodyweight push exercise.',
        videoUrl: 'https://www.youtube.com/embed/IODxDxX7oi4', muscleGroups: ['Chest', 'Triceps', 'Shoulders', 'Core'],
        sets: [
          { id: 'ogcb-d1-ex5-s1', targetReps: 'To Failure (or 10-15 strict)' },
          { id: 'ogcb-d1-ex5-s2', targetReps: 'To Failure (or 10-15 strict)' },
          { id: 'ogcb-d1-ex5-s3', targetReps: 'To Failure (or 10-15 strict)' },
        ],
      },
      {
        id: 'ogcb-d1-ex6', name: 'Triceps Pushdowns (Cable)', targetWeight: 'Light-Moderate', unit: 'reps',
        description: 'Triceps isolation using cables.',
        videoUrl: 'https://www.youtube.com/embed/2-LAMcpzODU', muscleGroups: ['Triceps'],
        sets: [
          { id: 'ogcb-d1-ex6-s1', targetReps: '10-15' },
          { id: 'ogcb-d1-ex6-s2', targetReps: '10-15' },
          { id: 'ogcb-d1-ex6-s3', targetReps: '10-15' },
        ],
      },
      {
        id: 'ogcb-d1-ex7', name: 'Lateral Raises (Dumbbell)', targetWeight: 'Light', unit: 'reps',
        description: 'Isolation for side deltoids.',
        videoUrl: 'https://www.youtube.com/embed/3VcKaXpzqRo', muscleGroups: ['Shoulders (Lateral)'],
        sets: [
          { id: 'ogcb-d1-ex7-s1', targetReps: '12-15' },
          { id: 'ogcb-d1-ex7-s2', targetReps: '12-15' },
          { id: 'ogcb-d1-ex7-s3', targetReps: '12-15' },
        ],
      },
      {
        id: 'ogcb-d1-ex8', name: 'Core: Plank', targetWeight: 'Bodyweight', unit: 's', isCore: true,
        description: 'Core stability exercise.',
        videoUrl: 'https://www.youtube.com/embed/ASdvN_XEl_c', muscleGroups: ['Core', 'Abs'],
        sets: [
          { id: 'ogcb-d1-ex8-s1', targetReps: '45-60', unit: 's' },
          { id: 'ogcb-d1-ex8-s2', targetReps: '45-60', unit: 's' },
          { id: 'ogcb-d1-ex8-s3', targetReps: '45-60', unit: 's' },
        ],
      },
    ],
  },
  {
    id: 'ogcb-day2',
    dayName: 'Tuesday',
    title: 'Lower Body (Gym Focus)',
    mapsToActualDayOfWeek: 2,
    notes: 'Warm-up: 5-10 min light cardio & dynamic stretches. Cool-down: 5-10 min static stretches.',
    exercises: [
      {
        id: 'ogcb-d2-ex1', name: 'Barbell Back Squat', targetWeight: 'Moderate-Heavy', unit: 'reps',
        description: 'Compound leg strength exercise.',
        videoUrl: 'https://www.youtube.com/embed/ultWZbUMPL8', muscleGroups: ['Quads', 'Glutes', 'Hamstrings', 'Core'],
        sets: [
          { id: 'ogcb-d2-ex1-s1', targetReps: '6-10' },
          { id: 'ogcb-d2-ex1-s2', targetReps: '6-10' },
          { id: 'ogcb-d2-ex1-s3', targetReps: '6-10' },
        ],
      },
      {
        id: 'ogcb-d2-ex2', name: 'Romanian Deadlifts (RDLs)', targetWeight: 'Moderate', unit: 'reps',
        description: 'Compound exercise for hamstrings and glutes.',
        videoUrl: 'https://www.youtube.com/embed/JCXUYuzwNrM', muscleGroups: ['Hamstrings', 'Glutes', 'Lower Back'],
        sets: [
          { id: 'ogcb-d2-ex2-s1', targetReps: '8-12' },
          { id: 'ogcb-d2-ex2-s2', targetReps: '8-12' },
          { id: 'ogcb-d2-ex2-s3', targetReps: '8-12' },
        ],
      },
      {
        id: 'ogcb-d2-ex3', name: 'Leg Press', targetWeight: 'Moderate', unit: 'reps',
        description: 'Overall leg development using a machine.',
        videoUrl: 'https://www.youtube.com/embed/IZxyjW7MPJQ', muscleGroups: ['Quads', 'Glutes', 'Hamstrings'],
        sets: [
          { id: 'ogcb-d2-ex3-s1', targetReps: '10-15' },
          { id: 'ogcb-d2-ex3-s2', targetReps: '10-15' },
          { id: 'ogcb-d2-ex3-s3', targetReps: '10-15' },
        ],
      },
      {
        id: 'ogcb-d2-ex4', name: 'Leg Extensions', targetWeight: 'Light-Moderate', unit: 'reps',
        description: 'Quadriceps isolation.',
        videoUrl: 'https://www.youtube.com/embed/YyvSfVjQeL0', muscleGroups: ['Quads'],
        sets: [
          { id: 'ogcb-d2-ex4-s1', targetReps: '12-15' },
          { id: 'ogcb-d2-ex4-s2', targetReps: '12-15' },
          { id: 'ogcb-d2-ex4-s3', targetReps: '12-15' },
        ],
      },
      {
        id: 'ogcb-d2-ex5', name: 'Hamstring Curls', targetWeight: 'Light-Moderate', unit: 'reps',
        description: 'Hamstring isolation.',
        videoUrl: 'https://www.youtube.com/embed/F488k67BTmA', muscleGroups: ['Hamstrings'],
        sets: [
          { id: 'ogcb-d2-ex5-s1', targetReps: '12-15' },
          { id: 'ogcb-d2-ex5-s2', targetReps: '12-15' },
          { id: 'ogcb-d2-ex5-s3', targetReps: '12-15' },
        ],
      },
      {
        id: 'ogcb-d2-ex6', name: 'Calf Raises (Standing or Seated)', targetWeight: 'Moderate', unit: 'reps',
        description: 'Calf isolation.',
        videoUrl: 'https://www.youtube.com/embed/JbyjNymZOt0', muscleGroups: ['Calves'],
        sets: [
          { id: 'ogcb-d2-ex6-s1', targetReps: '15-20' },
          { id: 'ogcb-d2-ex6-s2', targetReps: '15-20' },
          { id: 'ogcb-d2-ex6-s3', targetReps: '15-20' },
        ],
      },
      {
        id: 'ogcb-d2-ex7', name: 'Core: Hanging Leg Raises (or Lying Leg Raises)', targetWeight: 'Bodyweight', unit: 'reps', isCore: true,
        description: 'Targets lower abs.',
        videoUrl: 'https://www.youtube.com/embed/1A0Sqg_M39k', muscleGroups: ['Abs (Lower)', 'Hip Flexors'],
        sets: [
          { id: 'ogcb-d2-ex7-s1', targetReps: '15-20' },
          { id: 'ogcb-d2-ex7-s2', targetReps: '15-20' },
          { id: 'ogcb-d2-ex7-s3', targetReps: '15-20' },
        ],
      },
    ],
  },
  {
    id: 'ogcb-day3',
    dayName: 'Wednesday',
    title: 'Upper Body - Pull Focus',
    mapsToActualDayOfWeek: 3,
    notes: 'Warm-up: 5-10 min light cardio & dynamic stretches. Cool-down: 5-10 min static stretches.',
    exercises: [
      {
        id: 'ogcb-d3-ex1', name: 'Pull-ups (Assisted, Banded, or Bodyweight)', targetWeight: 'Bodyweight/Assisted', unit: 'reps',
        description: 'Calisthenics compound for back width and biceps.',
        videoUrl: 'https://www.youtube.com/embed/eGo4IYlbE5g', muscleGroups: ['Lats', 'Biceps', 'Upper Back'],
        sets: [
          { id: 'ogcb-d3-ex1-s1', targetReps: 'To Failure (or 6-10)' },
          { id: 'ogcb-d3-ex1-s2', targetReps: 'To Failure (or 6-10)' },
          { id: 'ogcb-d3-ex1-s3', targetReps: 'To Failure (or 6-10)' },
        ],
      },
      {
        id: 'ogcb-d3-ex2', name: 'Barbell Rows or Dumbbell Rows', targetWeight: 'Moderate', unit: 'reps',
        description: 'Compound exercise for back thickness.',
        videoUrl: 'https://www.youtube.com/embed/G8l_8chR5BE', muscleGroups: ['Lats', 'Rhomboids', 'Traps', 'Biceps'],
        sets: [
          { id: 'ogcb-d3-ex2-s1', targetReps: '8-12' },
          { id: 'ogcb-d3-ex2-s2', targetReps: '8-12' },
          { id: 'ogcb-d3-ex2-s3', targetReps: '8-12' },
        ],
      },
      {
        id: 'ogcb-d3-ex3', name: 'Lat Pulldown (Cable)', targetWeight: 'Moderate', unit: 'reps',
        description: 'Machine exercise for back width.',
        videoUrl: 'https://www.youtube.com/embed/lueEJGjTuPQ', muscleGroups: ['Lats', 'Biceps'],
        sets: [
          { id: 'ogcb-d3-ex3-s1', targetReps: '10-15' },
          { id: 'ogcb-d3-ex3-s2', targetReps: '10-15' },
          { id: 'ogcb-d3-ex3-s3', targetReps: '10-15' },
        ],
      },
      {
        id: 'ogcb-d3-ex4', name: 'Inverted Rows (Bodyweight Rows)', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'Bodyweight back exercise. Adjust bar height to change difficulty.',
        videoUrl: 'https://www.youtube.com/embed/D7jvi0tN84U', muscleGroups: ['Upper Back', 'Lats', 'Biceps'],
        sets: [
          { id: 'ogcb-d3-ex4-s1', targetReps: '10-15' },
          { id: 'ogcb-d3-ex4-s2', targetReps: '10-15' },
          { id: 'ogcb-d3-ex4-s3', targetReps: '10-15' },
        ],
      },
      {
        id: 'ogcb-d3-ex5', name: 'Chin-ups (Assisted, Banded, or Bodyweight)', targetWeight: 'Bodyweight/Assisted', unit: 'reps',
        description: 'Calisthenics exercise emphasizing biceps and back.',
        videoUrl: 'https://www.youtube.com/embed/ZUndn_jJqM0', muscleGroups: ['Biceps', 'Lats'],
        sets: [
          { id: 'ogcb-d3-ex5-s1', targetReps: 'To Failure (or 6-10)' },
          { id: 'ogcb-d3-ex5-s2', targetReps: 'To Failure (or 6-10)' },
          { id: 'ogcb-d3-ex5-s3', targetReps: 'To Failure (or 6-10)' },
        ],
      },
      {
        id: 'ogcb-d3-ex6', name: 'Bicep Curls (Dumbbell or Barbell)', targetWeight: 'Light-Moderate', unit: 'reps',
        description: 'Biceps isolation.',
        videoUrl: 'https://www.youtube.com/embed/ykJmrZ5v0Oo', muscleGroups: ['Biceps'],
        sets: [
          { id: 'ogcb-d3-ex6-s1', targetReps: '10-15' },
          { id: 'ogcb-d3-ex6-s2', targetReps: '10-15' },
          { id: 'ogcb-d3-ex6-s3', targetReps: '10-15' },
        ],
      },
      {
        id: 'ogcb-d3-ex7', name: 'Face Pulls (Cable)', targetWeight: 'Light', unit: 'reps',
        description: 'For rear delts and upper back health.',
        videoUrl: 'https://www.youtube.com/embed/rep-qVOkqgk', muscleGroups: ['Shoulders (Rear)', 'Traps', 'Rhomboids'],
        sets: [
          { id: 'ogcb-d3-ex7-s1', targetReps: '15-20' },
          { id: 'ogcb-d3-ex7-s2', targetReps: '15-20' },
          { id: 'ogcb-d3-ex7-s3', targetReps: '15-20' },
        ],
      },
      {
        id: 'ogcb-d3-ex8', name: 'Core: Russian Twists', targetWeight: 'Bodyweight or Light Weight', unit: 'reps', isCore: true,
        description: 'Targets obliques and rotational core strength.',
        videoUrl: 'https://www.youtube.com/embed/wkD8rjkodUI', muscleGroups: ['Obliques', 'Abs', 'Core'],
        sets: [
          { id: 'ogcb-d3-ex8-s1', targetReps: '15-20 per side' },
          { id: 'ogcb-d3-ex8-s2', targetReps: '15-20 per side' },
          { id: 'ogcb-d3-ex8-s3', targetReps: '15-20 per side' },
        ],
      },
    ],
  },
  {
    id: 'ogcb-day4',
    dayName: 'Thursday',
    title: 'Full Body Calisthenics & Core',
    mapsToActualDayOfWeek: 4,
    notes: 'Warm-up: 5-10 min light cardio & dynamic stretches. Perform strength exercises as a circuit. Cool-down: 5-10 min static stretches.',
    exercises: [
      {
        id: 'ogcb-d4-ex1-pistol', name: 'Pistol Squats (Assisted or Progression)', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'Unilateral leg strength. Use assistance if needed, or progress from single-leg box squats.',
        videoUrl: 'https://www.youtube.com/embed/vq5-vdgJc0I', muscleGroups: ['Quads', 'Glutes', 'Balance'],
        sets: [
          { id: 'ogcb-d4-ex1-pistol-s1', targetReps: '5-8 per leg' },
          { id: 'ogcb-d4-ex1-pistol-s2', targetReps: '5-8 per leg' },
          { id: 'ogcb-d4-ex1-pistol-s3', targetReps: '5-8 per leg' },
        ],
        notes: 'Part of Calisthenics Strength Circuit.',
      },
      {
        id: 'ogcb-d4-ex1-archer', name: 'Archer Push-ups or Pseudo Planche Push-ups', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'Advanced pushing progression.',
        videoUrl: 'https://www.youtube.com/embed/hHXW1q4iJ08', muscleGroups: ['Chest', 'Shoulders', 'Triceps', 'Core'],
        sets: [
          { id: 'ogcb-d4-ex1-archer-s1', targetReps: '5-8 per side/total' },
          { id: 'ogcb-d4-ex1-archer-s2', targetReps: '5-8 per side/total' },
          { id: 'ogcb-d4-ex1-archer-s3', targetReps: '5-8 per side/total' },
        ],
        notes: 'Part of Calisthenics Strength Circuit.',
      },
      {
        id: 'ogcb-d4-ex1-frontlever', name: 'Tuck Front Lever Holds (or progressions)', targetWeight: 'Bodyweight', unit: 's', isSkill: true,
        description: 'Isometric back and core strength. Progress from tuck front lever rows if needed.',
        videoUrl: 'https://www.youtube.com/embed/placeholder', muscleGroups: ['Lats', 'Core', 'Abs'],
        sets: [
          { id: 'ogcb-d4-ex1-frontlever-s1', targetReps: '10-20', unit: 's' },
          { id: 'ogcb-d4-ex1-frontlever-s2', targetReps: '10-20', unit: 's' },
          { id: 'ogcb-d4-ex1-frontlever-s3', targetReps: '10-20', unit: 's' },
        ],
        notes: 'Part of Calisthenics Strength Circuit.',
      },
      {
        id: 'ogcb-d4-ex1-lsit', name: 'L-Sit Holds (or progressions)', targetWeight: 'Bodyweight', unit: 's', isCore: true, isSkill: true,
        description: 'Core compression and arm support strength. Progress from tucked L-sit if needed.',
        videoUrl: 'https://www.youtube.com/embed/PzAmVcjY2X8', muscleGroups: ['Core', 'Abs', 'Hip Flexors', 'Triceps'],
        sets: [
          { id: 'ogcb-d4-ex1-lsit-s1', targetReps: '10-20', unit: 's' },
          { id: 'ogcb-d4-ex1-lsit-s2', targetReps: '10-20', unit: 's' },
          { id: 'ogcb-d4-ex1-lsit-s3', targetReps: '10-20', unit: 's' },
        ],
        notes: 'Part of Calisthenics Strength Circuit.',
      },
      {
        id: 'ogcb-d4-core1', name: 'Core: Side Plank', targetWeight: 'Bodyweight', unit: 's', isCore: true,
        description: 'Oblique stability.',
        videoUrl: 'https://www.youtube.com/embed/1h4g9sQxV0A', muscleGroups: ['Obliques', 'Core'],
        sets: [
          { id: 'ogcb-d4-core1-s1', targetReps: '30-45 per side', unit: 's' },
          { id: 'ogcb-d4-core1-s2', targetReps: '30-45 per side', unit: 's' },
          { id: 'ogcb-d4-core1-s3', targetReps: '30-45 per side', unit: 's' },
        ],
        notes: 'Dedicated Core Work (Choose 2-3).',
      },
      {
        id: 'ogcb-d4-core2', name: 'Core: Bird-Dog', targetWeight: 'Bodyweight', unit: 'reps', isCore: true,
        description: 'Core stability and coordination.',
        videoUrl: 'https://www.youtube.com/embed/wiFNA3sqjCA', muscleGroups: ['Core', 'Glutes', 'Lower Back'],
        sets: [
          { id: 'ogcb-d4-core2-s1', targetReps: '10-12 per side' },
          { id: 'ogcb-d4-core2-s2', targetReps: '10-12 per side' },
          { id: 'ogcb-d4-core2-s3', targetReps: '10-12 per side' },
        ],
        notes: 'Dedicated Core Work (Choose 2-3).',
      },
      {
        id: 'ogcb-d4-core3', name: 'Core: Flutter Kicks', targetWeight: 'Bodyweight', unit: 'reps', isCore: true,
        description: 'Lower abs endurance.',
        videoUrl: 'https://www.youtube.com/embed/placeholder', muscleGroups: ['Abs (Lower)', 'Hip Flexors'],
        sets: [
          { id: 'ogcb-d4-core3-s1', targetReps: '20-30 per leg' },
          { id: 'ogcb-d4-core3-s2', targetReps: '20-30 per leg' },
          { id: 'ogcb-d4-core3-s3', targetReps: '20-30 per leg' },
        ],
        notes: 'Dedicated Core Work (Choose 2-3).',
      },
    ],
  },
  {
    id: 'ogcb-day5',
    dayName: 'Friday',
    title: 'Hybrid Strength & Active Recovery',
    mapsToActualDayOfWeek: 5,
    notes: 'Warm-up: 5-10 min light cardio & dynamic stretches. Cool-down: 5-10 min static stretches. Focus on controlled form.',
    exercises: [
      {
        id: 'ogcb-d5-ex1', name: 'Goblet Squats or Dumbbell RDLs', targetWeight: 'Light-Moderate', unit: 'reps',
        description: 'Focus on controlled movement and form, not max weight.',
        videoUrl: 'https://www.youtube.com/embed/MeW1bB741zY', muscleGroups: ['Quads', 'Glutes', 'Hamstrings', 'Core'],
        sets: [
          { id: 'ogcb-d5-ex1-s1', targetReps: '12-15' },
          { id: 'ogcb-d5-ex1-s2', targetReps: '12-15' },
          { id: 'ogcb-d5-ex1-s3', targetReps: '12-15' },
        ],
      },
      {
        id: 'ogcb-d5-ex2', name: 'Single-Arm Dumbbell Rows', targetWeight: 'Moderate', unit: 'reps',
        description: 'Unilateral back and core stability.',
        videoUrl: 'https://www.youtube.com/embed/pYcpY20QaE8', muscleGroups: ['Lats', 'Rhomboids', 'Biceps', 'Core'],
        sets: [
          { id: 'ogcb-d5-ex2-s1', targetReps: '10-12 per arm' },
          { id: 'ogcb-d5-ex2-s2', targetReps: '10-12 per arm' },
          { id: 'ogcb-d5-ex2-s3', targetReps: '10-12 per arm' },
        ],
      },
      {
        id: 'ogcb-d5-ex3', name: 'Push-up Progression (Kneeling, Standard, or Incline)', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'Focus on good form, stop before true muscle failure.',
        videoUrl: 'https://www.youtube.com/embed/IODxDxX7oi4', muscleGroups: ['Chest', 'Triceps', 'Shoulders'],
        sets: [
          { id: 'ogcb-d5-ex3-s1', targetReps: 'Comfortable Failure' },
          { id: 'ogcb-d5-ex3-s2', targetReps: 'Comfortable Failure' },
          { id: 'ogcb-d5-ex3-s3', targetReps: 'Comfortable Failure' },
        ],
      },
      {
        id: 'ogcb-d5-ex4', name: 'Inverted Rows (Bodyweight Rows)', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'Controlled bodyweight back exercise.',
        videoUrl: 'https://www.youtube.com/embed/D7jvi0tN84U', muscleGroups: ['Upper Back', 'Lats', 'Biceps'],
        sets: [
          { id: 'ogcb-d5-ex4-s1', targetReps: '10-15' },
          { id: 'ogcb-d5-ex4-s2', targetReps: '10-15' },
          { id: 'ogcb-d5-ex4-s3', targetReps: '10-15' },
        ],
      },
      {
        id: 'ogcb-d5-ex5', name: 'Core: Dead Bug', targetWeight: 'Bodyweight', unit: 'reps', isCore: true,
        description: 'Core stability and anti-extension.',
        videoUrl: 'https://www.youtube.com/embed/g_BYB4vAoqs', muscleGroups: ['Core', 'Abs'],
        sets: [
          { id: 'ogcb-d5-ex5-s1', targetReps: '10-12 per side' },
          { id: 'ogcb-d5-ex5-s2', targetReps: '10-12 per side' },
          { id: 'ogcb-d5-ex5-s3', targetReps: '10-12 per side' },
        ],
      },
      {
        id: 'ogcb-d5-ex6', name: 'Flexibility & Mobility Session', targetWeight: 'Bodyweight', unit: 'min', isActivity: true, isMobility: true, isStretch: true,
        description: '10-15 minutes on static stretches, focusing on areas that feel tight (hips, hamstrings, chest, shoulders) and/or foam rolling.',
        videoUrl: 'https://www.youtube.com/embed/Sj_N63D0Zck', muscleGroups: ['Full Body'],
        sets: [{ id: 'ogcb-d5-ex6-s1', targetReps: '10-15', unit: 'min' }],
      },
    ],
  },
  {
    id: 'ogcb-day6',
    dayName: 'Saturday',
    title: 'Football',
    mapsToActualDayOfWeek: 6,
    notes: 'Focus on the game! Ensure proper warm-up and cool-down.',
    exercises: [
      {
        id: 'ogcb-d6-ex1', name: 'Football Game', targetWeight: 'N/A', unit: 'min', isMatch: true, isActivity: true,
        description: 'Competitive football match.',
        videoUrl: 'https://www.youtube.com/embed/placeholder', muscleGroups: ['Full Body', 'Cardio', 'Agility'],
        sets: [{ id: 'ogcb-d6-ex1-s1', targetReps: '90', unit: 'min' }],
      },
    ],
  },
  {
    id: 'ogcb-day7',
    dayName: 'Sunday',
    title: 'Complete Rest',
    mapsToActualDayOfWeek: 0,
    isRecovery: true,
    notes: 'Allow your body to fully recover and rebuild. Focus on good nutrition and hydration. Light walking or stretching is fine.',
    exercises: [
      {
        id: 'ogcb-d7-ex1', name: 'Rest Day Activities', targetWeight: 'N/A', unit: 'min', isActivity: true, isRecovery: true,
        description: 'Complete rest from intense training. Light activities like walking are okay.',
        videoUrl: 'https://www.youtube.com/embed/placeholder', muscleGroups: ['N/A'],
        sets: [{ id: 'ogcb-d7-ex1-s1', targetReps: 'Full Day' }],
      },
    ],
  },
];


export const defaultNamedPlans: NamedWorkoutPlan[] = [
  {
    id: 'optimized-gym-calisthenics-blended-plan',
    name: 'Optimized Gym & Calisthenics Blend',
    description: 'A balanced plan incorporating gym equipment and calisthenics for strength, skill, and conditioning, with integrated core work.',
    plan: optimizedGymCalisthenicsPlan,
    isActive: true,
  },
  {
    id: 'default-strength-plan',
    name: 'Original Strength Plan',
    description: 'A balanced strength training program focusing on major compound lifts and accessory work.',
    plan: defaultStrengthPlan,
    isActive: false,
  },
  {
    id: 'calisthenics-beast-plan',
    name: 'Calisthenics Beast (Gym-Optimized)',
    description: 'A calisthenics program leveraging gym access for enhanced progressions and skill work.',
    plan: calisthenicsBeastPlan,
    isActive: false,
  },
];

const dayStringToNumberMap: Record<string, number> = {
  sunday: 0,
  monday: 1,
  tuesday: 2,
  wednesday: 3,
  thursday: 4,
  friday: 5,
  saturday: 6,
};

// Helper function to get a specific workout day from a given WeeklyPlan
export const getWorkoutByDayFromPlan = (plan: WeeklyPlan, dayIdOrNumericDay: string | number): WorkoutDay | undefined => {
  // First, try direct ID match (case-insensitive) if dayIdOrNumericDay is a string
  if (typeof dayIdOrNumericDay === 'string') {
    const directMatch = plan.find(day => day.id.toLowerCase() === dayIdOrNumericDay.toLowerCase());
    if (directMatch) {
      return directMatch;
    }
  }

  // Determine the numeric day of the week
  let numericDayOfWeek: number;
  if (typeof dayIdOrNumericDay === 'number') {
    numericDayOfWeek = dayIdOrNumericDay;
  } else if (typeof dayIdOrNumericDay === 'string' && dayStringToNumberMap.hasOwnProperty(dayIdOrNumericDay.toLowerCase())) {
    numericDayOfWeek = dayStringToNumberMap[dayIdOrNumericDay.toLowerCase()];
  } else {
    return undefined;
  }

  const mappedDay = plan.find(day => day.mapsToActualDayOfWeek === numericDayOfWeek);
  return mappedDay;
};


// Helper function to get all unique exercises from a specific WeeklyPlan or all default plans
export const getAllExercisesFromPlan = (specificPlan?: WeeklyPlan): Exercise[] => {
  const allExercisesMap = new Map<string, Exercise>();
  const plansToSearch = specificPlan ? [ { id: 'custom', name: 'Custom', plan: specificPlan, isActive: true, description: 'Custom Plan'} ] : defaultNamedPlans;

  plansToSearch.forEach(namedPlan => {
    namedPlan.plan.forEach(day => {
      day.exercises.forEach(exercise => {
        if (!allExercisesMap.has(exercise.id)) {
          allExercisesMap.set(exercise.id, exercise);
        }
      });
    });
  });
  // Also include exercises from the standalone library for broader autocomplete
  exerciseLibrary[0].exercises.forEach(exercise => {
     if (!allExercisesMap.has(exercise.id)) {
        allExercisesMap.set(exercise.id, exercise);
      }
  });
  return Array.from(allExercisesMap.values()).sort((a,b) => a.name.localeCompare(b.name));
};

export const getExerciseById = (exerciseId: string, specificPlan?: WeeklyPlan): Exercise | undefined => {
  const plansToSearch = specificPlan ? [{ plan: specificPlan, name: "Specific", id:"specific", isActive: true, description: "Specific Plan" }] : defaultNamedPlans;
  
  for (const namedPlan of plansToSearch) {
    for (const day of namedPlan.plan) {
      const foundExercise = day.exercises.find(ex => ex.id === exerciseId);
      if (foundExercise) {
        return foundExercise;
      }
    }
  }
  // Check the library as a fallback
  const libraryExercise = exerciseLibrary[0].exercises.find(ex => ex.id === exerciseId);
  if (libraryExercise) return libraryExercise;

  // Last resort: search all known exercises if not found in specific or default plans
  const allExercises = getAllExercisesFromPlan(); // This will include library
  return allExercises.find(ex => ex.id === exerciseId);
};

// getDays for a specific plan
export const getDaysForPlan = (plan: WeeklyPlan) => plan.filter(day => day.id !== 'exercise-library').map(day => ({ id: day.id, dayName: day.dayName, title: day.title }));


// Old weeklyPlan export - DEPRECATED for direct use, use defaultNamedPlans and plan service instead
export const weeklyPlan: WeeklyPlan = defaultStrengthPlan; // Kept for any direct legacy imports, but should be phased out.

export { defaultStrengthPlan as originalWeeklyPlan }; // Exporting with a more specific name if needed

