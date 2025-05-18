
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
        videoUrl: 'https://www.youtube.com/embed/qEwKCR5JCog', // DB Version
        // Alt Barbell: https://www.youtube.com/embed/-t7fuZ0KhDA
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
        videoUrl: 'https://www.youtube.com/embed/sVsrKCSqYic', // Ab Wheel
        // Alt Cable Crunches: https://www.youtube.com/embed/Fz8mx4U7g2Y
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
        videoUrl: '', // No specific general video
        muscleGroups: ['Legs', 'Cardio'],
        sets: [{ id: 'sat-ex2-set1', targetReps: '3 × 20 m all‐out' }],
      },
      {
        id: 'sat-ex3', name: 'Football Match', isMatch: true, isActivity: true, targetWeight: 'N/A',
        description: 'Participation in a football (soccer) match.',
        videoUrl: '', // Not applicable
        muscleGroups: ['Full Body', 'Cardio', 'Agility'],
        sets: [{ id: 'sat-ex3-set1', targetReps: 'Match play (~90 min)' }],
      },
      {
        id: 'sat-ex4', name: 'Cool-Down Jog/Walk', targetWeight: 'bodyweight', isActivity: true,
        description: 'Light jogging or walking to gradually lower heart rate and aid recovery after the match.',
        videoUrl: '', // Not applicable
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
    exercises: [
      {
        id: 'sun-ex1', name: 'Walking', isRecovery: true, isActivity: true, targetWeight: 'bodyweight',
        description: 'Low-intensity walking to promote blood flow and recovery without stressing the body.',
        videoUrl: '', // Not applicable
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
  {
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
  }
];

export const getWorkoutByDay = (dayId: string) => {
  return weeklyPlan.find(day => day.id.toLowerCase() === dayId.toLowerCase());
};

// Helper function to get all unique exercises for static param generation or autocomplete
export const getAllExercisesFromPlan = (): Exercise[] => {
  const allExercisesMap = new Map<string, Exercise>();
  weeklyPlan.forEach(day => {
    // Do not include exercises from 'exercise-library' in the list of *plannable* exercises shown in UI,
    // but do include them for autocomplete lookup. The filter for plannable exercises happens where getDays is used.
    // For getAllExercisesFromPlan, we want everything for autocomplete.
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
  // This fallback is less critical now that getAllExercisesFromPlan sources from weeklyPlan directly,
  // but kept for robustness.
  const allExercises = getAllExercisesFromPlan();
  return allExercises.find(ex => ex.id === exerciseId);
};

// getDays is used to populate the workout plan page.
// It should not include the 'exercise-library' pseudo-day.
export const getDays = () => weeklyPlan.filter(day => day.id !== 'exercise-library').map(day => ({ id: day.id, dayName: day.dayName, title: day.title }));


    