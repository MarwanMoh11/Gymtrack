
import type { WeeklyPlan, Exercise, NamedWorkoutPlan, WorkoutDay } from '@/types/workout';

const pplHybridPlan: WeeklyPlan = [
  {
    id: 'ppl-monday',
    dayName: 'Monday',
    title: 'Push Day',
    mapsToActualDayOfWeek: 1,
    notes: 'Focus on compound movements first. Maintain good form.',
    exercises: [
      {
        id: 'ppl-mon-ex1', name: 'Incline DB Bench Press', targetWeight: '22.5 kg', unit: 'reps',
        description: 'A variation of the bench press that targets the upper chest muscles more effectively due to the inclined angle of the bench.',
        videoUrl: 'https://www.youtube.com/embed/8iPEnn-ltC8',
        muscleGroups: ['Chest (Upper)', 'Shoulders (Front)', 'Triceps'],
        sets: [
          { id: 'ppl-mon-ex1-set1', exerciseId: 'ppl-mon-ex1', targetReps: '8-12' },
          { id: 'ppl-mon-ex1-set2', exerciseId: 'ppl-mon-ex1', targetReps: '8-12' },
          { id: 'ppl-mon-ex1-set3', exerciseId: 'ppl-mon-ex1', targetReps: '8-12' },
        ],
      },
      {
        id: 'ppl-mon-ex2', name: 'Dips', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'A compound bodyweight exercise that primarily targets the triceps and chest. Performed using parallel bars.',
        videoUrl: 'https://www.youtube.com/embed/2z8JmcrW-As',
        muscleGroups: ['Triceps', 'Chest (Lower)', 'Shoulders (Front)'],
        sets: [
          { id: 'ppl-mon-ex2-set1', exerciseId: 'ppl-mon-ex2', targetReps: 'To Failure' },
          { id: 'ppl-mon-ex2-set2', exerciseId: 'ppl-mon-ex2', targetReps: 'To Failure' },
          { id: 'ppl-mon-ex2-set3', exerciseId: 'ppl-mon-ex2', targetReps: 'To Failure' },
        ],
      },
      {
        id: 'ppl-mon-ex3', name: 'Seated Shoulder Press', targetWeight: '65 kg', unit: 'reps',
        description: 'An overhead pressing exercise, usually performed with a barbell or dumbbells while seated, targeting the deltoid muscles.',
        muscleGroups: ['Shoulders (All Heads)', 'Triceps'],
        videoUrl: 'https://www.youtube.com/embed/qEwKCR5JCog',
        sets: [
          { id: 'ppl-mon-ex3-set1', exerciseId: 'ppl-mon-ex3', targetReps: '8-12' },
          { id: 'ppl-mon-ex3-set2', exerciseId: 'ppl-mon-ex3', targetReps: '8-12' },
          { id: 'ppl-mon-ex3-set3', exerciseId: 'ppl-mon-ex3', targetReps: '8-12' },
        ],
      },
      {
        id: 'ppl-mon-ex4', name: 'Pike Push-Ups', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'A challenging bodyweight exercise that simulates an overhead press, targeting the shoulders and triceps.',
        videoUrl: 'https://www.youtube.com/embed/mYdOknQ_24M',
        muscleGroups: ['Shoulders', 'Triceps'],
        sets: [
          { id: 'ppl-mon-ex4-set1', exerciseId: 'ppl-mon-ex4', targetReps: '10-15' },
          { id: 'ppl-mon-ex4-set2', exerciseId: 'ppl-mon-ex4', targetReps: '10-15' },
          { id: 'ppl-mon-ex4-set3', exerciseId: 'ppl-mon-ex4', targetReps: '10-15' },
        ],
      },
      {
        id: 'ppl-mon-ex5', name: 'Triceps Rope Pushdown', targetWeight: '5th stack', unit: 'reps',
        description: 'An isolation exercise for the triceps using a cable machine and a rope attachment.',
        videoUrl: 'https://www.youtube.com/embed/vB5OHro6kAA',
        muscleGroups: ['Triceps'],
        sets: [
          { id: 'ppl-mon-ex5-set1', exerciseId: 'ppl-mon-ex5', targetReps: '12-15' },
          { id: 'ppl-mon-ex5-set2', exerciseId: 'ppl-mon-ex5', targetReps: '12-15' },
          { id: 'ppl-mon-ex5-set3', exerciseId: 'ppl-mon-ex5', targetReps: '12-15' },
        ],
      },
      {
        id: 'ppl-mon-ex6', name: 'Plank', unit: 's', isCore: true, targetWeight: 'Bodyweight',
        description: 'An isometric core strength exercise that involves maintaining a position similar to a push-up for the maximum possible time.',
        videoUrl: 'https://www.youtube.com/embed/pDafg-Bv-s8',
        muscleGroups: ['Core (Abs, Obliques, Lower Back)'],
        sets: [
          { id: 'ppl-mon-ex6-set1', exerciseId: 'ppl-mon-ex6', targetReps: '60', unit: 's' },
          { id: 'ppl-mon-ex6-set2', exerciseId: 'ppl-mon-ex6', targetReps: '60', unit: 's' },
          { id: 'ppl-mon-ex6-set3', exerciseId: 'ppl-mon-ex6', targetReps: '60', unit: 's' },
        ],
      },
    ],
  },
  {
    id: 'ppl-tuesday',
    dayName: 'Tuesday',
    title: 'Pull Day',
    mapsToActualDayOfWeek: 2,
    exercises: [
      {
        id: 'ppl-tue-ex1', name: 'Pull-Ups', targetWeight: 'Bodyweight or Assisted', unit: 'reps',
        description: 'A bodyweight exercise where you hang from a bar and pull yourself up until your chin is over it. Excellent for building back width.',
        videoUrl: 'https://www.youtube.com/embed/e_5z3A4D6Fk',
        muscleGroups: ['Latissimus Dorsi', 'Biceps', 'Upper Back'],
        sets: [
          { id: 'ppl-tue-ex1-set1', exerciseId: 'ppl-tue-ex1', targetReps: 'To Failure' },
          { id: 'ppl-tue-ex1-set2', exerciseId: 'ppl-tue-ex1', targetReps: 'To Failure' },
          { id: 'ppl-tue-ex1-set3', exerciseId: 'ppl-tue-ex1', targetReps: 'To Failure' },
        ],
      },
      {
        id: 'ppl-tue-ex2', name: 'Seated Cable Rows', targetWeight: '12th stack', unit: 'reps',
        description: 'A machine-based rowing exercise that targets the mid-back and is excellent for improving posture.',
        videoUrl: 'https://www.youtube.com/embed/GZbfZ033f74',
        muscleGroups: ['Rhomboids', 'Latissimus Dorsi', 'Biceps'],
        sets: [
          { id: 'ppl-tue-ex2-set1', exerciseId: 'ppl-tue-ex2', targetReps: '10-12' },
          { id: 'ppl-tue-ex2-set2', exerciseId: 'ppl-tue-ex2', targetReps: '10-12' },
          { id: 'ppl-tue-ex2-set3', exerciseId: 'ppl-tue-ex2', targetReps: '10-12' },
        ],
      },
      {
        id: 'ppl-tue-ex3', name: 'Inverted Rows', unit: 'reps', targetWeight: 'Bodyweight',
        description: 'A bodyweight rowing exercise where you lie under a fixed bar and pull your chest up to it. A great precursor to pull-ups.',
        videoUrl: 'https://www.youtube.com/embed/hXTc1mDn2yY',
        muscleGroups: ['Rhomboids', 'Lats', 'Biceps', 'Posterior Deltoids'],
        sets: [
          { id: 'ppl-tue-ex3-set1', exerciseId: 'ppl-tue-ex3', targetReps: '10-15' },
          { id: 'ppl-tue-ex3-set2', exerciseId: 'ppl-tue-ex3', targetReps: '10-15' },
          { id: 'ppl-tue-ex3-set3', exerciseId: 'ppl-tue-ex3', targetReps: '10-15' },
        ],
      },
      {
        id: 'ppl-tue-ex4', name: 'Dumbbell Preacher Curl', targetWeight: '10 kg', unit: 'reps',
        description: 'An isolation curl performed on a preacher bench, which prevents cheating and maximizes bicep contraction.',
        videoUrl: 'https://www.youtube.com/embed/fIWP-FRFNU0',
        muscleGroups: ['Biceps'],
        sets: [
          { id: 'ppl-tue-ex4-set1', exerciseId: 'ppl-tue-ex4', targetReps: '10-12' },
          { id: 'ppl-tue-ex4-set2', exerciseId: 'ppl-tue-ex4', targetReps: '10-12' },
          { id: 'ppl-tue-ex4-set3', exerciseId: 'ppl-tue-ex4', targetReps: '10-12' },
        ],
      },
      {
        id: 'ppl-tue-ex5', name: 'Face Pulls', targetWeight: 'cable', unit: 'reps',
        description: 'A crucial exercise for shoulder health, targeting the rear deltoids and upper back muscles using a rope attachment on a cable machine.',
        videoUrl: 'https://www.youtube.com/embed/eIq5CB9wyoE',
        muscleGroups: ['Posterior Deltoids', 'Rhomboids', 'Traps'],
        sets: [
          { id: 'ppl-tue-ex5-set1', exerciseId: 'ppl-tue-ex5', targetReps: '15-20' },
          { id: 'ppl-tue-ex5-set2', exerciseId: 'ppl-tue-ex5', targetReps: '15-20' },
          { id: 'ppl-tue-ex5-set3', exerciseId: 'ppl-tue-ex5', targetReps: '15-20' },
        ],
      },
      {
        id: 'ppl-tue-ex6', name: 'Hanging Leg Raises', unit: 'reps', isCore: true, targetWeight: 'Bodyweight',
        description: 'A more advanced version of the hanging knee raise where you keep your legs straight, increasing the difficulty.',
        videoUrl: 'https://www.youtube.com/embed/Pr1ieGZ5atk',
        muscleGroups: ['Lower Rectus Abdominis', 'Obliques', 'Hip Flexors'],
        sets: [
          { id: 'ppl-tue-ex6-set1', exerciseId: 'ppl-tue-ex6', targetReps: '15-20' },
          { id: 'ppl-tue-ex6-set2', exerciseId: 'ppl-tue-ex6', targetReps: '15-20' },
          { id: 'ppl-tue-ex6-set3', exerciseId: 'ppl-tue-ex6', targetReps: '15-20' },
        ],
      },
    ],
  },
  {
    id: 'ppl-wednesday',
    dayName: 'Wednesday',
    title: 'Leg Day',
    mapsToActualDayOfWeek: 3,
    exercises: [
      {
        id: 'ppl-wed-ex1', name: 'Leg Press', targetWeight: '60 kg', unit: 'reps',
        description: 'A machine-based exercise where you press a weighted platform away with your feet. Great for building leg mass with less strain on the back.',
        videoUrl: 'https://www.youtube.com/embed/s8-89_iT_aQ',
        muscleGroups: ['Quadriceps', 'Glutes', 'Hamstrings'],
        sets: [
          { id: 'ppl-wed-ex1-set1', exerciseId: 'ppl-wed-ex1', targetReps: '10-12' },
          { id: 'ppl-wed-ex1-set2', exerciseId: 'ppl-wed-ex1', targetReps: '10-12' },
          { id: 'ppl-wed-ex1-set3', exerciseId: 'ppl-wed-ex1', targetReps: '10-12' },
        ],
      },
      {
        id: 'ppl-wed-ex2', name: 'Bodyweight Squats', unit: 'reps', targetWeight: 'Bodyweight',
        description: 'A fundamental lower body exercise. For added intensity, can be performed as jump squats.',
        videoUrl: 'https://www.youtube.com/embed/bEv6CCg2BC8',
        muscleGroups: ['Quadriceps', 'Glutes', 'Hamstrings', 'Calves'],
        sets: [
          { id: 'ppl-wed-ex2-set1', exerciseId: 'ppl-wed-ex2', targetReps: '20-25' },
          { id: 'ppl-wed-ex2-set2', exerciseId: 'ppl-wed-ex2', targetReps: '20-25' },
          { id: 'ppl-wed-ex2-set3', exerciseId: 'ppl-wed-ex2', targetReps: '20-25' },
        ],
      },
      {
        id: 'ppl-wed-ex3', name: 'Leg Curls (Lying or Seated)', targetWeight: '22 kg', unit: 'reps',
        description: 'An isolation machine exercise that targets the hamstrings. Can be performed either lying face down or seated.',
        videoUrl: 'https://www.youtube.com/embed/1Tq3QdYUuHs',
        muscleGroups: ['Hamstrings'],
        sets: [
          { id: 'ppl-wed-ex3-set1', exerciseId: 'ppl-wed-ex3', targetReps: '12-15' },
          { id: 'ppl-wed-ex3-set2', exerciseId: 'ppl-wed-ex3', targetReps: '12-15' },
          { id: 'ppl-wed-ex3-set3', exerciseId: 'ppl-wed-ex3', targetReps: '12-15' },
        ],
      },
      {
        id: 'ppl-wed-ex4', name: 'Glute Bridges', unit: 'reps', targetWeight: 'Bodyweight',
        description: 'Targets the glutes and hamstrings. Can be progressed to a single-leg variation for increased difficulty.',
        videoUrl: 'https://www.youtube.com/embed/8bbE64Nu_2U',
        muscleGroups: ['Glutes', 'Hamstrings'],
        sets: [
          { id: 'ppl-wed-ex4-set1', exerciseId: 'ppl-wed-ex4', targetReps: '15-20' },
          { id: 'ppl-wed-ex4-set2', exerciseId: 'ppl-wed-ex4', targetReps: '15-20' },
          { id: 'ppl-wed-ex4-set3', exerciseId: 'ppl-wed-ex4', targetReps: '15-20' },
        ],
      },
       {
        id: 'ppl-wed-ex5', name: 'Seated Calf Raises', targetWeight: 'Machine Stack', unit: 'reps',
        description: 'An isolation exercise that primarily targets the soleus muscle of the calf due to the knee being bent.',
        videoUrl: 'https://www.youtube.com/embed/JflgI0jZNtA',
        muscleGroups: ['Soleus'],
        sets: [
          { id: 'ppl-wed-ex5-set1', exerciseId: 'ppl-wed-ex5', targetReps: '15-20' },
          { id: 'ppl-wed-ex5-set2', exerciseId: 'ppl-wed-ex5', targetReps: '15-20' },
          { id: 'ppl-wed-ex5-set3', exerciseId: 'ppl-wed-ex5', targetReps: '15-20' },
        ],
      },
      {
        id: 'ppl-wed-ex6', name: 'Bodyweight Calf Raises', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'An isolation exercise for the larger gastrocnemius muscle of the calf. Can be done on a machine or with free weights.',
        videoUrl: 'https://www.youtube.com/embed/Jfl_g_h_AnA',
        muscleGroups: ['Gastrocnemius', 'Soleus'],
        sets: [
          { id: 'ppl-wed-ex6-set1', exerciseId: 'ppl-wed-ex6', targetReps: 'To Failure' },
          { id: 'ppl-wed-ex6-set2', exerciseId: 'ppl-wed-ex6', targetReps: 'To Failure' },
          { id: 'ppl-wed-ex6-set3', exerciseId: 'ppl-wed-ex6', targetReps: 'To Failure' },
        ],
      },
    ],
  },
  {
    id: 'ppl-thursday',
    dayName: 'Thursday',
    title: 'Rest Day',
    mapsToActualDayOfWeek: 4,
    isRecovery: true,
    exercises: [{
      id: 'ppl-thu-rest', name: 'Active Recovery or Full Rest', isActivity: true,
      description: 'Focus on recovery. Light activities like walking or stretching are encouraged.',
      muscleGroups: ['N/A'],
      sets: [{ id: 'ppl-thu-rest-s1', exerciseId: 'ppl-thu-rest', targetReps: 'Full day' }]
    }]
  },
  {
    id: 'ppl-friday',
    dayName: 'Friday',
    title: 'Upper Body Day',
    mapsToActualDayOfWeek: 5,
    exercises: [
      {
        id: 'ppl-fri-ex1', name: 'Push-Ups', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'A classic bodyweight exercise performed by pushing your body up from the floor. Excellent for overall chest and triceps development.',
        videoUrl: 'https://www.youtube.com/embed/IODxDxX7oi4',
        muscleGroups: ['Pectoralis Major', 'Triceps', 'Deltoids', 'Core'],
        sets: [
          { id: 'ppl-fri-ex1-set1', exerciseId: 'ppl-fri-ex1', targetReps: '15-20' },
          { id: 'ppl-fri-ex1-set2', exerciseId: 'ppl-fri-ex1', targetReps: '15-20' },
          { id: 'ppl-fri-ex1-set3', exerciseId: 'ppl-fri-ex1', targetReps: '15-20' },
        ],
      },
      {
        id: 'ppl-fri-ex2', name: 'Wide Lat Pulldown', targetWeight: '12th stack', unit: 'reps',
        description: 'A machine exercise that simulates a pull-up. Great for targeting the lats and building back width.',
        videoUrl: 'https://www.youtube.com/embed/0oe_dj_G9oU',
        muscleGroups: ['Latissimus Dorsi', 'Biceps'],
        sets: [
          { id: 'ppl-fri-ex2-set1', exerciseId: 'ppl-fri-ex2', targetReps: '10-12' },
          { id: 'ppl-fri-ex2-set2', exerciseId: 'ppl-fri-ex2', targetReps: '10-12' },
          { id: 'ppl-fri-ex2-set3', exerciseId: 'ppl-fri-ex2', targetReps: '10-12' },
        ],
      },
      {
        id: 'ppl-fri-ex3', name: 'Chin-Ups', targetWeight: 'Bodyweight or Assisted', unit: 'reps',
        description: 'Similar to pull-ups but with an underhand (supinated) grip, which increases bicep involvement.',
        videoUrl: 'https://www.youtube.com/embed/b-2tM2n_p0M',
        muscleGroups: ['Latissimus Dorsi', 'Biceps'],
        sets: [
          { id: 'ppl-fri-ex3-set1', exerciseId: 'ppl-fri-ex3', targetReps: 'To Failure' },
          { id: 'ppl-fri-ex3-set2', exerciseId: 'ppl-fri-ex3', targetReps: 'To Failure' },
          { id: 'ppl-fri-ex3-set3', exerciseId: 'ppl-fri-ex3', targetReps: 'To Failure' },
        ],
      },
      {
        id: 'ppl-fri-ex4', name: 'Cable Crossovers (Low to High)', targetWeight: '2nd stack', unit: 'reps',
        description: 'Standing between two low pulleys, you pull the handles upwards and across your body, targeting the upper chest.',
        videoUrl: 'https://www.youtube.com/embed/Iwe6AmxVf7o',
        muscleGroups: ['Upper Pectoralis', 'Serratus Anterior'],
        sets: [
          { id: 'ppl-fri-ex4-set1', exerciseId: 'ppl-fri-ex4', targetReps: '12-15' },
          { id: 'ppl-fri-ex4-set2', exerciseId: 'ppl-fri-ex4', targetReps: '12-15' },
          { id: 'ppl-fri-ex4-set3', exerciseId: 'ppl-fri-ex4', 'targetReps': '12-15' },
        ],
      },
      {
        id: 'ppl-fri-ex5', name: 'Lateral Raises', targetWeight: '7.5 kg', unit: 'reps',
        description: 'An isolation exercise for the lateral (side) deltoids. You raise dumbbells out to your sides until they are at shoulder height.',
        videoUrl: 'https://www.youtube.com/embed/3VcKaXpzqRo',
        muscleGroups: ['Lateral Deltoids'],
        sets: [
          { id: 'ppl-fri-ex5-set1', exerciseId: 'ppl-fri-ex5', targetReps: '15-20' },
          { id: 'ppl-fri-ex5-set2', exerciseId: 'ppl-fri-ex5', targetReps: '15-20' },
          { id: 'ppl-fri-ex5-set3', exerciseId: 'ppl-fri-ex5', targetReps: '15-20' },
        ],
      },
      {
        id: 'ppl-fri-ex6', name: 'L-Sit Holds', targetWeight: 'Bodyweight', isCore: true, unit: 's',
        description: 'Advanced core exercise. Use parallel bars or floor. Aim for straight legs and 90-degree angle.',
        videoUrl: 'https://www.youtube.com/embed/PzAmVcjY2X8',
        muscleGroups: ['Core', 'Hip Flexors', 'Triceps', 'Shoulders'],
        sets: [
          { id: 'ppl-fri-ex6-set1', exerciseId: 'ppl-fri-ex6', targetReps: '15-30', unit: 's' },
          { id: 'ppl-fri-ex6-set2', exerciseId: 'ppl-fri-ex6', targetReps: '15-30', unit: 's' },
          { id: 'ppl-fri-ex6-set3', exerciseId: 'ppl-fri-ex6', targetReps: '15-30', unit: 's' },
        ],
      },
    ],
  },
  {
    id: 'ppl-saturday',
    dayName: 'Saturday',
    title: 'Lower Body Day',
    mapsToActualDayOfWeek: 6,
    exercises: [
      {
        id: 'ppl-sat-ex1', name: 'Bulgarian Split Squats', targetWeight: 'Bodyweight or DBs', unit: 'reps',
        description: 'A single-leg squat variation with the rear foot elevated on a bench, which intensely targets the quads and glutes of the front leg.',
        videoUrl: 'https://www.youtube.com/embed/2C-uNgKwPLE',
        muscleGroups: ['Quadriceps', 'Glutes', 'Hamstrings'],
        sets: [
          { id: 'ppl-sat-ex1-set1', exerciseId: 'ppl-sat-ex1', targetReps: '10-12 per leg' },
          { id: 'ppl-sat-ex1-set2', exerciseId: 'ppl-sat-ex1', targetReps: '10-12 per leg' },
          { id: 'ppl-sat-ex1-set3', exerciseId: 'ppl-sat-ex1', targetReps: '10-12 per leg' },
        ],
      },
      {
        id: 'ppl-sat-ex2', name: 'Romanian Deadlifts (RDLs)', targetWeight: '15 kg', unit: 'reps',
        description: 'A deadlift variation focusing on the hip hinge with minimal knee bend to primarily target the hamstrings and glutes.',
        videoUrl: 'https://www.youtube.com/embed/2z8JmcrW-As',
        muscleGroups: ['Hamstrings', 'Glutes', 'Erector Spinae'],
        sets: [
          { id: 'ppl-sat-ex2-set1', exerciseId: 'ppl-sat-ex2', targetReps: '10-12' },
          { id: 'ppl-sat-ex2-set2', exerciseId: 'ppl-sat-ex2', targetReps: '10-12' },
          { id: 'ppl-sat-ex2-set3', exerciseId: 'ppl-sat-ex2', targetReps: '10-12' },
        ],
      },
      {
        id: 'ppl-sat-ex3', name: 'Leg Extensions', targetWeight: '25 kg', unit: 'reps',
        description: 'An isolation machine exercise that specifically targets the quadriceps muscles.',
        videoUrl: 'https://www.youtube.com/embed/YyvSfVjQeL0',
        muscleGroups: ['Quadriceps'],
        sets: [
          { id: 'ppl-sat-ex3-set1', exerciseId: 'ppl-sat-ex3', targetReps: '15-20' },
          { id: 'ppl-sat-ex3-set2', exerciseId: 'ppl-sat-ex3', targetReps: '15-20' },
          { id: 'ppl-sat-ex3-set3', exerciseId: 'ppl-sat-ex3', targetReps: '15-20' },
        ],
      },
      {
        id: 'ppl-sat-ex4', name: 'Cossack Squats', targetWeight: 'Bodyweight', unit: 'reps', isMobility: true,
        description: 'A dynamic lateral squat that improves hip, groin, and ankle mobility while building unilateral leg strength.',
        videoUrl: 'https://www.youtube.com/embed/tpLnfSQ8vrY',
        muscleGroups: ['Adductors', 'Glutes', 'Quads', 'Mobility'],
        sets: [
          { id: 'ppl-sat-ex4-set1', exerciseId: 'ppl-sat-ex4', targetReps: '8-10 per side' },
          { id: 'ppl-sat-ex4-set2', exerciseId: 'ppl-sat-ex4', targetReps: '8-10 per side' },
          { id: 'ppl-sat-ex4-set3', exerciseId: 'ppl-sat-ex4', targetReps: '8-10 per side' },
        ],
      },
      {
        id: 'ppl-sat-ex5', name: 'Hip Adductor Machine', targetWeight: 'Machine Stack', unit: 'reps',
        description: 'Isolation exercise for inner thighs (hip adductors). Squeeze legs inward against resistance.',
        videoUrl: 'https://www.youtube.com/embed/WDY2cO8444s',
        muscleGroups: ['Hip Adductors', 'Groin'],
        sets: [
          { id: 'ppl-sat-ex5-set1', exerciseId: 'ppl-sat-ex5', targetReps: '15-20' },
          { id: 'ppl-sat-ex5-set2', exerciseId: 'ppl-sat-ex5', targetReps: '15-20' },
          { id: 'ppl-sat-ex5-set3', exerciseId: 'ppl-sat-ex5', targetReps: '15-20' },
        ],
      },
      {
        id: 'ppl-sat-ex6', name: 'Side Planks', targetWeight: 'Bodyweight', unit: 's', isCore: true,
        description: 'An isometric exercise where you support your body on one forearm, targeting the obliques and improving core stability.',
        videoUrl: 'https://www.youtube.com/embed/Z64142k_S84',
        muscleGroups: ['Obliques', 'Transverse Abdominis'],
        sets: [
          { id: 'ppl-sat-ex6-set1', exerciseId: 'ppl-sat-ex6', targetReps: '45', unit: 's' },
          { id: 'ppl-sat-ex6-set2', exerciseId: 'ppl-sat-ex6', targetReps: '45', unit: 's' },
          { id: 'ppl-sat-ex6-set3', exerciseId: 'ppl-sat-ex6', targetReps: '45', unit: 's' },
        ],
      },
    ],
  },
  {
    id: 'ppl-sunday',
    dayName: 'Sunday',
    title: 'Rest Day',
    mapsToActualDayOfWeek: 0,
    isRecovery: true,
    exercises: [{
      id: 'ppl-sun-rest', name: 'Rest Day', isActivity: true,
      description: 'Focus on recovery, nutrition, and hydration.',
      muscleGroups: ['N/A'],
      sets: [{ id: 'ppl-sun-rest-s1', exerciseId: 'ppl-sun-rest', targetReps: 'Full day' }]
    }]
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
        id: 'cal-mon-skill-hs', name: 'Handstand Practice', isSkill: true, unit: 's',
        description: 'Use wall for support if needed. Focus on stacking joints, controlled breathing. If comfortable, practice free handstand attempts.',
        videoUrl: 'https://www.youtube.com/embed/xsk6P93s5ww', muscleGroups: ['Shoulders', 'Core', 'Triceps', 'Traps'],
        sets: [
          { id: 'cal-mon-skill-hs-s1', exerciseId: 'cal-mon-skill-hs', targetReps: '30-60', unit: 's' },
          { id: 'cal-mon-skill-hs-s2', exerciseId: 'cal-mon-skill-hs', targetReps: '30-60', unit: 's' },
          { id: 'cal-mon-skill-hs-s3', exerciseId: 'cal-mon-skill-hs', targetReps: '30-60', unit: 's' },
        ],
      },
      {
        id: 'cal-mon-pullups-weighted', name: 'Weighted Pull-Ups / Lat Pulldown', unit: 'reps',
        targetWeight: 'Bodyweight / Add 2.5-10 kg / Lat Pulldown 80% BW',
        description: 'Use weight belt/dumbbell or Lat Pulldown machine for assistance/regression. Slow, controlled reps.',
        videoUrl: 'https://www.youtube.com/embed/huR4B2aDhKk', muscleGroups: ['Lats', 'Biceps', 'Upper Back'],
        sets: [
          { id: 'cal-mon-pullups-w-s1', exerciseId: 'cal-mon-pullups-weighted', targetReps: '5-8' },
          { id: 'cal-mon-pullups-w-s2', exerciseId: 'cal-mon-pullups-weighted', targetReps: '5-8' },
          { id: 'cal-mon-pullups-w-s3', exerciseId: 'cal-mon-pullups-weighted', targetReps: '5-8' },
          { id: 'cal-mon-pullups-w-s4', exerciseId: 'cal-mon-pullups-weighted', targetReps: '5-8' },
        ],
      },
      {
        id: 'cal-mon-archer-pullups', name: 'Archer Pull-Ups / Wide Pull-Ups', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'Perform Archer Pull-Ups, focusing on shifting weight to one arm, or Wide Pull-Ups for broader lat engagement.',
        videoUrl: 'https://www.youtube.com/embed/IWj7JgD0gB8', muscleGroups: ['Lats', 'Biceps', 'Shoulders'],
        sets: [
          { id: 'cal-mon-archer-s1', exerciseId: 'cal-mon-archer-pullups', targetReps: '4-6 (each side for Archer)' },
          { id: 'cal-mon-archer-s2', exerciseId: 'cal-mon-archer-pullups', targetReps: '4-6 (each side for Archer)' },
          { id: 'cal-mon-archer-s3', exerciseId: 'cal-mon-archer-pullups', targetReps: '4-6 (each side for Archer)' },
        ],
      },
      {
        id: 'cal-mon-inverted-rows', name: 'Australian Pull-Ups (Inverted Rows)', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'Use Smith Machine bar or low bar in power cage. Adjust bar height to change difficulty.',
        videoUrl: 'https://www.youtube.com/embed/D7jvi0tN84U', muscleGroups: ['Upper Back', 'Biceps', 'Lats'],
        sets: [
          { id: 'cal-mon-invrow-s1', exerciseId: 'cal-mon-inverted-rows', targetReps: '10-15' },
          { id: 'cal-mon-invrow-s2', exerciseId: 'cal-mon-inverted-rows', targetReps: '10-15' },
          { id: 'cal-mon-invrow-s3', exerciseId: 'cal-mon-inverted-rows', targetReps: '10-15' },
        ],
      },
      {
        id: 'cal-mon-lsit', name: 'L-Sit Holds', targetWeight: 'Bodyweight', isCore: true, unit: 's',
        description: 'Use parallel bars, dip station, or floor. Aim for straight legs and 90-degree angle.',
        videoUrl: 'https://www.youtube.com/embed/PzAmVcjY2X8', muscleGroups: ['Core', 'Hip Flexors', 'Triceps', 'Shoulders'],
        sets: [
          { id: 'cal-mon-lsit-s1', exerciseId: 'cal-mon-lsit', targetReps: '10-20', unit: 's' },
          { id: 'cal-mon-lsit-s2', exerciseId: 'cal-mon-lsit', targetReps: '10-20', unit: 's' },
          { id: 'cal-mon-lsit-s3', exerciseId: 'cal-mon-lsit', targetReps: '10-20', unit: 's' },
        ],
      },
      {
        id: 'cal-mon-hanging-leg-raises', name: 'Hanging Leg Raises / Toes to Bar', targetWeight: 'Bodyweight', isCore: true, unit: 'reps',
        description: 'Hang from a pull-up bar. Raise legs straight up (or knees for regression) towards the bar.',
        videoUrl: 'https://www.youtube.com/embed/Pr1ieGZ5atk', muscleGroups: ['Abs (Lower)', 'Hip Flexors', 'Core'],
        sets: [
          { id: 'cal-mon-hlr-s1', exerciseId: 'cal-mon-hanging-leg-raises', targetReps: '10-15' },
          { id: 'cal-mon-hlr-s2', exerciseId: 'cal-mon-hanging-leg-raises', targetReps: '10-15' },
          { id: 'cal-mon-hlr-s3', exerciseId: 'cal-mon-hanging-leg-raises', targetReps: '10-15' },
        ],
      },
      {
        id: 'cal-mon-plank', name: 'Core – Plank', targetWeight: 'Bodyweight', unit: 's', isCore: true,
        description: 'Maintain a straight line from head to heels, engaging the core. Avoid letting hips sag.',
        videoUrl: 'https://www.youtube.com/embed/pDafg-Bv-s8', muscleGroups: ['Core', 'Abs', 'Obliques', 'Lower Back'],
        sets: [
          { id: 'cal-mon-plank-s1', exerciseId: 'cal-mon-plank', targetReps: '60-90', unit: 's' },
          { id: 'cal-mon-plank-s2', exerciseId: 'cal-mon-plank', targetReps: '60-90', unit: 's' },
          { id: 'cal-mon-plank-s3', exerciseId: 'cal-mon-plank', targetReps: 'to failure', unit: 's' },
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
          { id: 'cal-tue-pistol-s1', exerciseId: 'cal-tue-pistol-squats', targetReps: '5-8 (each leg)' },
          { id: 'cal-tue-pistol-s2', exerciseId: 'cal-tue-pistol-squats', targetReps: '5-8 (each leg)' },
          { id: 'cal-tue-pistol-s3', exerciseId: 'cal-tue-pistol-squats', targetReps: '5-8 (each leg)' },
        ],
      },
      {
        id: 'cal-tue-bulgarian-split-squats', name: 'Bulgarian Split Squats', targetWeight: 'Bodyweight (or add DBs)', unit: 'reps',
        description: 'Rear foot elevated on a bench or plyo box. Focus on controlled descent and driving up through the front heel.',
        videoUrl: 'https://www.youtube.com/embed/2C-uNgKwPLE', muscleGroups: ['Quads', 'Glutes', 'Hamstrings'],
        sets: [
          { id: 'cal-tue-bss-s1', exerciseId: 'cal-tue-bulgarian-split-squats', targetReps: '10-12 (each leg)' },
          { id: 'cal-tue-bss-s2', exerciseId: 'cal-tue-bulgarian-split-squats', targetReps: '10-12 (each leg)' },
          { id: 'cal-tue-bss-s3', exerciseId: 'cal-tue-bulgarian-split-squats', targetReps: '10-12 (each leg)' },
        ],
      },
      {
        id: 'cal-tue-glute-bridges', name: 'Glute Bridges / Single Leg Glute Bridges', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'Lie on your back, knees bent, feet flat. Lift hips towards the ceiling, squeezing glutes. Progress to single leg.',
        videoUrl: 'https://www.youtube.com/embed/8bbE64Nu_2U', muscleGroups: ['Glutes', 'Hamstrings', 'Core'],
        sets: [
          { id: 'cal-tue-gb-s1', exerciseId: 'cal-tue-glute-bridges', targetReps: '15-20' },
          { id: 'cal-tue-gb-s2', exerciseId: 'cal-tue-glute-bridges', targetReps: '15-20' },
          { id: 'cal-tue-gb-s3', exerciseId: 'cal-tue-glute-bridges', targetReps: '15-20' },
        ],
      },
      {
        id: 'cal-tue-calf-raises', name: 'Calf Raises (Bodyweight or Smith Machine)', targetWeight: 'Bodyweight / Add light weight', unit: 'reps',
        description: 'Stand with balls of feet on an elevated surface (optional). Raise heels as high as possible, then lower slowly.',
        videoUrl: 'https://www.youtube.com/embed/Jfl_g_h_AnA', muscleGroups: ['Calves'],
        sets: [
          { id: 'cal-tue-cr-s1', exerciseId: 'cal-tue-calf-raises', targetReps: '25-30' },
          { id: 'cal-tue-cr-s2', exerciseId: 'cal-tue-calf-raises', targetReps: '25-30' },
          { id: 'cal-tue-cr-s3', exerciseId: 'cal-tue-calf-raises', targetReps: '25-30' },
        ],
      },
      {
        id: 'cal-tue-mobility-circuit', name: 'Mobility Circuit', isMobility: true, unit: 's',
        description: 'Perform 2-3 rounds, 30-45s per exercise. Focus on range of motion and breathing.',
        videoUrl: 'https://www.youtube.com/embed/L_xrDAtykMI', // General mobility routine
        muscleGroups: ['Full Body', 'Flexibility'],
        sets: [
          { id: 'cal-tue-mob-s1', exerciseId: 'cal-tue-mobility-circuit', targetReps: '30-45s/side', notes: 'Couch Stretch' },
          { id: 'cal-tue-mob-s2', exerciseId: 'cal-tue-mobility-circuit', targetReps: '30-45s/side', notes: 'Pigeon Stretch' },
          { id: 'cal-tue-mob-s3', exerciseId: 'cal-tue-mobility-circuit', targetReps: '30-45s/side', notes: 'Hip Flexor Stretch' },
          { id: 'cal-tue-mob-s4', exerciseId: 'cal-tue-mobility-circuit', targetReps: '30-45', notes: 'Cat-Cow' },
          { id: 'cal-tue-mob-s5', exerciseId: 'cal-tue-mobility-circuit', targetReps: '30-45', notes: 'Thoracic Spine Rotations' },
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
          { id: 'cal-wed-skill-planche-s1', exerciseId: 'cal-wed-skill-planche', targetReps: '5-8' },
          { id: 'cal-wed-skill-planche-s2', exerciseId: 'cal-wed-skill-planche', targetReps: '5-8' },
          { id: 'cal-wed-skill-planche-s3', exerciseId: 'cal-wed-skill-planche', targetReps: '5-8' },
        ],
      },
      {
        id: 'cal-wed-dips-weighted', name: 'Weighted Dips / Assisted Dips', unit: 'reps',
        targetWeight: 'Bodyweight / Add 2.5-10 kg / Use assisted dip machine',
        description: 'Use weight belt/dumbbell or Dip Machine for assistance/regression. Controlled descent, full range of motion.',
        videoUrl: 'https://www.youtube.com/embed/2z8JmcrW-As', muscleGroups: ['Triceps', 'Chest (Lower)', 'Shoulders (Front)'],
        sets: [
          { id: 'cal-wed-dips-w-s1', exerciseId: 'cal-wed-dips-weighted', targetReps: '8-12' },
          { id: 'cal-wed-dips-w-s2', exerciseId: 'cal-wed-dips-weighted', targetReps: '8-12' },
          { id: 'cal-wed-dips-w-s3', exerciseId: 'cal-wed-dips-weighted', targetReps: '8-12' },
          { id: 'cal-wed-dips-w-s4', exerciseId: 'cal-wed-dips-weighted', targetReps: '8-12' },
        ],
      },
      {
        id: 'cal-wed-decline-pushups', name: 'Decline Push-Ups', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'Feet elevated on a bench or plyo box to target upper chest and shoulders more intensely.',
        videoUrl: 'https://www.youtube.com/embed/Pkj8LLRsoDw', muscleGroups: ['Chest (Upper)', 'Shoulders (Front)', 'Triceps'],
        sets: [
          { id: 'cal-wed-decline-s1', exerciseId: 'cal-wed-decline-pushups', targetReps: '12-15' },
          { id: 'cal-wed-decline-s2', exerciseId: 'cal-wed-decline-pushups', targetReps: '12-15' },
          { id: 'cal-wed-decline-s3', exerciseId: 'cal-wed-decline-pushups', targetReps: '12-15' },
        ],
      },
      {
        id: 'cal-wed-pike-hspu', name: 'Pike Push-Ups / Wall Handstand Push-Ups', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'Pike push-ups with feet on floor or elevated for progression. Or, Wall Handstand Push-Ups (facing wall or back to wall).',
        videoUrl: 'https://www.youtube.com/embed/mYdOknQ_24M', muscleGroups: ['Shoulders', 'Triceps', 'Traps'],
        sets: [
          { id: 'cal-wed-pike-s1', exerciseId: 'cal-wed-pike-hspu', targetReps: '8-12' },
          { id: 'cal-wed-pike-s2', exerciseId: 'cal-wed-pike-hspu', targetReps: '8-12' },
          { id: 'cal-wed-pike-s3', exerciseId: 'cal-wed-pike-hspu', targetReps: '8-12' },
        ],
      },
      {
        id: 'cal-wed-triceps-ext', name: 'Bodyweight Triceps Extensions', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'E.g., Triceps extensions on parallel bars/rings (if available), or close-grip push-ups with elbows tucked.',
        videoUrl: 'https://www.youtube.com/embed/h3g3x1q4R3A', // Example: Triceps extension on bar
        muscleGroups: ['Triceps'],
        sets: [
          { id: 'cal-wed-tricep-s1', exerciseId: 'cal-wed-triceps-ext', targetReps: '10-15' },
          { id: 'cal-wed-tricep-s2', exerciseId: 'cal-wed-triceps-ext', targetReps: '10-15' },
          { id: 'cal-wed-tricep-s3', exerciseId: 'cal-wed-triceps-ext', targetReps: '10-15' },
        ],
      },
      {
        id: 'cal-wed-dragon-flags', name: 'Dragon Flags / Reverse Crunches', targetWeight: 'Bodyweight', isCore: true, unit: 'reps',
        description: 'Use sturdy bench or decline bench. Dragon flags for advanced core strength, reverse crunches for regression.',
        videoUrl: 'https://www.youtube.com/embed/moyh9_hIIA0', muscleGroups: ['Abs', 'Core', 'Obliques'],
        sets: [
          { id: 'cal-wed-dragon-s1', exerciseId: 'cal-wed-dragon-flags', targetReps: '8-12' },
          { id: 'cal-wed-dragon-s2', exerciseId: 'cal-wed-dragon-flags', targetReps: '8-12' },
          { id: 'cal-wed-dragon-s3', exerciseId: 'cal-wed-dragon-flags', targetReps: '8-12' },
        ],
      },
      {
        id: 'cal-wed-side-plank', name: 'Core – Side Plank', targetWeight: 'Bodyweight', unit: 's', isCore: true,
        description: 'Maintain a straight line from head to feet, supporting body on one forearm/hand. Engage obliques.',
        videoUrl: 'https://www.youtube.com/embed/Z64142k_S84', muscleGroups: ['Obliques', 'Core', 'Abs'],
        sets: [
          { id: 'cal-wed-sideplank-s1', exerciseId: 'cal-wed-side-plank', targetReps: '45-60 (each side)', unit: 's' },
          { id: 'cal-wed-sideplank-s2', exerciseId: 'cal-wed-side-plank', targetReps: '45-60 (each side)', unit: 's' },
          { id: 'cal-wed-sideplank-s3', exerciseId: 'cal-wed-side-plank', targetReps: '45-60 (each side)', unit: 's' },
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
        sets: [{ id: 'cal-thu-cardio-s1', exerciseId: 'cal-thu-cardio', targetReps: '30-45', unit: 'min', notes: 'Light to moderate intensity' }],
      },
      {
        id: 'cal-thu-foam-roll', name: 'Foam Rolling', isFoamRoll: true, isMobility: true, unit: 'min',
        description: 'Use gym\'s foam rollers. Focus on Quads, Hamstrings, Glutes, Lats, Chest, Shoulders.',
        videoUrl: 'https://www.youtube.com/embed/fTvZ47nN3XU', // Full body foam roll
        muscleGroups: ['Full Body'],
        sets: [{ id: 'cal-thu-foam-s1', exerciseId: 'cal-thu-foam-roll', targetReps: '2-3 min per muscle group' }],
      },
      {
        id: 'cal-thu-static-stretch', name: 'Static Stretching', isStretch: true, isMobility: true, unit: 's',
        description: 'Hold each static stretch for 30 seconds, 2-3 times. Focus on major muscle groups.',
        videoUrl: 'https://www.youtube.com/embed/Sj_N63D0Zck', // Full body static stretch
        muscleGroups: ['Full Body', 'Flexibility'],
        sets: [{ id: 'cal-thu-stretch-s1', exerciseId: 'cal-thu-static-stretch', targetReps: '30s per stretch, 2-3x' }],
      },
      {
        id: 'cal-thu-joint-rotations', name: 'Joint Rotations & Mobility Drills', isMobility: true, unit: 'min',
        description: 'Ankle rotations, hip circles, arm circles, wrist stretches.',
        videoUrl: 'https://www.youtube.com/embed/83hWIc0997g', // Joint mobility routine
        muscleGroups: ['Joints', 'Full Body'],
        sets: [{ id: 'cal-thu-joint-s1', exerciseId: 'cal-thu-joint-rotations', targetReps: '5-10 min total' }],
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
        description: 'Use pull-up bar.', videoUrl: 'https://www.youtube.com/embed/e_5z3A4D6Fk', muscleGroups: ['Lats', 'Biceps'],
        sets: [{ id: 'cal-fri-pullups-s1', exerciseId: 'cal-fri-pullups', targetReps: 'Max (target 8-12)' }],
      },
      {
        id: 'cal-fri-pushups', name: 'Push-Ups', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'On floor or with push-up handles for wrist comfort.', videoUrl: 'https://www.youtube.com/embed/IODxDxX7oi4', muscleGroups: ['Chest', 'Triceps', 'Shoulders'],
        sets: [{ id: 'cal-fri-pushups-s1', exerciseId: 'cal-fri-pushups', targetReps: 'Max (target 15-25)' }],
      },
      {
        id: 'cal-fri-squats', name: 'Bodyweight Squats / Jump Squats', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'On gym floor. Jump squats for added intensity.', videoUrl: 'https://www.youtube.com/embed/bEv6CCg2BC8', muscleGroups: ['Quads', 'Glutes', 'Hamstrings'],
        sets: [{ id: 'cal-fri-squats-s1', exerciseId: 'cal-fri-squats', targetReps: '15-20' }],
      },
      {
        id: 'cal-fri-dips', name: 'Dips', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'Use dip station or parallel bars.', videoUrl: 'https://www.youtube.com/embed/c3ZGl4pAWiM', muscleGroups: ['Triceps', 'Chest', 'Shoulders'],
        sets: [{ id: 'cal-fri-dips-s1', exerciseId: 'cal-fri-dips', targetReps: 'Max (target 10-15)' }],
      },
      {
        id: 'cal-fri-inverted-rows', name: 'Inverted Rows', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'Use Smith Machine bar or low bar in power cage.', videoUrl: 'https://www.youtube.com/embed/hXTc1mDn2yY', muscleGroups: ['Upper Back', 'Biceps'],
        sets: [{ id: 'cal-fri-invrow-s1', exerciseId: 'cal-fri-inverted-rows', targetReps: '12-18' }],
      },
      {
        id: 'cal-fri-burpees', name: 'Burpees', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'Full body explosive movement.', videoUrl: 'https://www.youtube.com/embed/JZQA08SlJnM', muscleGroups: ['Full Body', 'Cardio'],
        sets: [{ id: 'cal-fri-burpees-s1', exerciseId: 'cal-fri-burpees', targetReps: '10-15' }],
      },
      {
        id: 'cal-fri-plank', name: 'Plank', targetWeight: 'Bodyweight', unit: 's', isCore: true,
        description: 'Hold with good form.', videoUrl: 'https://www.youtube.com/embed/pDafg-Bv-s8', muscleGroups: ['Core', 'Abs'],
        sets: [{ id: 'cal-fri-plank-s1', exerciseId: 'cal-fri-plank', targetReps: '45-60', unit: 's' }],
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
          { id: 'cal-sat-skill-flt', exerciseId: 'cal-sat-skill-focus', targetReps: 'max hold (5-10s)', notes: 'Front Lever Tucks: 3-5 sets' },
          { id: 'cal-sat-skill-pll', exerciseId: 'cal-sat-skill-focus', targetReps: 'max hold (5-10s)', notes: 'Planche Leans: 3-5 sets' },
          { id: 'cal-sat-skill-hsh', exerciseId: 'cal-sat-skill-focus', targetReps: 'max hold (20-40s)', notes: 'Handstand Holds: 3-5 sets' },
        ],
        notes: 'Choose 1-2 skills to focus on.'
      },
      {
        id: 'cal-sat-outdoor-activity', name: 'Outdoor Activity / Active Recreation', isActivity: true, unit: 'min',
        description: 'Hiking, cycling, swimming, playing a sport, or just a long walk.',
        videoUrl: 'https://www.youtube.com/embed/placeholder', muscleGroups: ['Full Body', 'Cardio'],
        sets: [{ id: 'cal-sat-outdoor-s1', exerciseId: 'cal-sat-outdoor-activity', targetReps: '60-90 min', unit: 'min', notes: 'Enjoyable, moderate intensity' }],
      },
    ],
  },
  {
    id: 'cal-sunday',
    dayName: 'Sunday',
    title: 'Complete Rest',
    mapsToActualDayOfWeek: 0,
    isRecovery: true,
    notes: 'Allow your body to fully recover and rebuild. Focus on good nutrition and hydration.',
    exercises: [
      {
        id: 'cal-sun-rest', name: 'Rest Day', isActivity: true,
        description: 'Focus on recovery, nutrition, and hydration. Light stretching if desired.',
        videoUrl: 'https://www.youtube.com/embed/placeholder', muscleGroups: ['N/A'],
        sets: [{ id: 'cal-sun-rest-s1', exerciseId: 'cal-sun-rest', targetReps: 'Full day' }],
      },
    ],
  },
];

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
        id: 'ogcb-d1-ex1', name: 'Machine Chest Press', targetWeight: '60 lbs / 30 lbs', unit: 'reps',
        description: 'A seated machine exercise that mimics the bench press in a safer, more controlled manner. Great for beginners.',
        videoUrl: 'https://www.youtube.com/embed/Xa9-6pYk0_U', muscleGroups: ['Pectoralis Major', 'Triceps', 'Deltoids'],
        sets: [
          { id: 'ogcb-d1-ex1-s1', exerciseId: 'ogcb-d1-ex1', targetReps: '6-10' },
          { id: 'ogcb-d1-ex1-s2', exerciseId: 'ogcb-d1-ex1', targetReps: '6-10' },
          { id: 'ogcb-d1-ex1-s3', exerciseId: 'ogcb-d1-ex1', targetReps: '6-10' },
        ],
      },
      {
        id: 'ogcb-d1-ex2', name: 'Overhead Press (Barbell or Dumbbell)', targetWeight: '65 lbs / 35 lbs', unit: 'reps',
        description: 'A compound lift, also known as the military press, where you press a barbell overhead from a standing or seated position.',
        videoUrl: 'https://www.youtube.com/embed/2yjwXTZQDDI', muscleGroups: ['Deltoids', 'Triceps', 'Traps'],
        sets: [
          { id: 'ogcb-d1-ex2-s1', exerciseId: 'ogcb-d1-ex2', targetReps: '6-10' },
          { id: 'ogcb-d1-ex2-s2', exerciseId: 'ogcb-d1-ex2', targetReps: '6-10' },
          { id: 'ogcb-d1-ex2-s3', exerciseId: 'ogcb-d1-ex2', targetReps: '6-10' },
        ],
      },
      {
        id: 'ogcb-d1-ex3', name: 'Incline Dumbbell Press', targetWeight: '25 lbs / 10 lbs', unit: 'reps',
        description: 'Using dumbbells on an incline bench to target the upper chest. The independent movement of dumbbells helps correct muscle imbalances.',
        videoUrl: 'https://www.youtube.com/embed/8iPEnn-ltC8', muscleGroups: ['Upper Pectoralis', 'Deltoids', 'Triceps'],
        sets: [
          { id: 'ogcb-d1-ex3-s1', exerciseId: 'ogcb-d1-ex3', targetReps: '8-12' },
          { id: 'ogcb-d1-ex3-s2', exerciseId: 'ogcb-d1-ex3', targetReps: '8-12' },
          { id: 'ogcb-d1-ex3-s3', exerciseId: 'ogcb-d1-ex3', targetReps: '8-12' },
        ],
      },
      {
        id: 'ogcb-d1-ex4', name: 'Chest Dips', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'Performed on parallel bars, leaning your torso forward emphasizes the chest muscles, particularly the lower chest.',
        videoUrl: 'https://www.youtube.com/embed/c3ZGl4pAWiM', muscleGroups: ['Lower Pectoralis', 'Triceps', 'Deltoids'],
        sets: [
          { id: 'ogcb-d1-ex4-s1', exerciseId: 'ogcb-d1-ex4', targetReps: '8-12' },
          { id: 'ogcb-d1-ex4-s2', exerciseId: 'ogcb-d1-ex4', targetReps: '8-12' },
          { id: 'ogcb-d1-ex4-s3', exerciseId: 'ogcb-d1-ex4', targetReps: '8-12' },
        ],
      },
      {
        id: 'ogcb-d1-ex5', name: 'Push-ups (Standard, Decline, or Pseudo Planche)', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'Progressive bodyweight push exercise.',
        videoUrl: 'https://www.youtube.com/embed/IODxDxX7oi4', muscleGroups: ['Chest', 'Triceps', 'Shoulders', 'Core'],
        sets: [
          { id: 'ogcb-d1-ex5-s1', exerciseId: 'ogcb-d1-ex5', targetReps: 'To Failure (or 10-15 strict)' },
          { id: 'ogcb-d1-ex5-s2', exerciseId: 'ogcb-d1-ex5', targetReps: 'To Failure (or 10-15 strict)' },
          { id: 'ogcb-d1-ex5-s3', exerciseId: 'ogcb-d1-ex5', targetReps: 'To Failure (or 10-15 strict)' },
        ],
      },
      {
        id: 'ogcb-d1-ex6', name: 'Triceps Pushdowns (Cable)', targetWeight: '40 lbs / 20 lbs', unit: 'reps',
        description: 'A common triceps isolation exercise on a cable machine. A rope allows for greater range of motion, while a bar allows for heavier weight.',
        videoUrl: 'https://www.youtube.com/embed/2-LAMcpzODU', muscleGroups: ['Triceps Brachii'],
        sets: [
          { id: 'ogcb-d1-ex6-s1', exerciseId: 'ogcb-d1-ex6', targetReps: '10-15' },
          { id: 'ogcb-d1-ex6-s2', exerciseId: 'ogcb-d1-ex6', targetReps: '10-15' },
          { id: 'ogcb-d1-ex6-s3', exerciseId: 'ogcb-d1-ex6', targetReps: '10-15' },
        ],
      },
      {
        id: 'ogcb-d1-ex7', name: 'Lateral Raises', targetWeight: '10 lbs / 5 lbs', unit: 'reps',
        description: 'An isolation exercise for the lateral (side) deltoids. You raise dumbbells out to your sides until they are at shoulder height.',
        videoUrl: 'https://www.youtube.com/embed/3VcKaXpzqRo', muscleGroups: ['Lateral Deltoids'],
        sets: [
          { id: 'ogcb-d1-ex7-s1', exerciseId: 'ogcb-d1-ex7', targetReps: '12-15' },
          { id: 'ogcb-d1-ex7-s2', exerciseId: 'ogcb-d1-ex7', targetReps: '12-15' },
          { id: 'ogcb-d1-ex7-s3', exerciseId: 'ogcb-d1-ex7', targetReps: '12-15' },
        ],
      },
      {
        id: 'ogcb-d1-ex8', name: 'Core: Plank', targetWeight: 'Bodyweight', unit: 's', isCore: true,
        description: 'An isometric core exercise where you hold a push-up-like position on your forearms, maintaining a straight line from head to heels.',
        videoUrl: 'https://www.youtube.com/embed/pDafg-Bv-s8', muscleGroups: ['Rectus Abdominis, Transverse Abdominis, Obliques'],
        sets: [
          { id: 'ogcb-d1-ex8-s1', exerciseId: 'ogcb-d1-ex8', targetReps: '45-60', unit: 's' },
          { id: 'ogcb-d1-ex8-s2', exerciseId: 'ogcb-d1-ex8', targetReps: '45-60', unit: 's' },
          { id: 'ogcb-d1-ex8-s3', exerciseId: 'ogcb-d1-ex8', targetReps: '45-60', unit: 's' },
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
        id: 'ogcb-d2-ex1', name: 'Barbell Back Squats', targetWeight: '95 lbs / 45 lbs', unit: 'reps',
        description: 'A foundational lower body exercise where you squat down with a barbell resting on your upper back. The "king" of leg exercises.',
        videoUrl: 'https://www.youtube.com/embed/bEv6CCg2BC8', muscleGroups: ['Quadriceps', 'Glutes', 'Hamstrings', 'Calves', 'Core'],
        sets: [
          { id: 'ogcb-d2-ex1-s1', exerciseId: 'ogcb-d2-ex1', targetReps: '6-10' },
          { id: 'ogcb-d2-ex1-s2', exerciseId: 'ogcb-d2-ex1', targetReps: '6-10' },
          { id: 'ogcb-d2-ex1-s3', exerciseId: 'ogcb-d2-ex1', targetReps: '6-10' },
        ],
      },
      {
        id: 'ogcb-d2-ex2', name: 'Romanian Deadlifts (RDLs)', targetWeight: '95 lbs / 55 lbs', unit: 'reps',
        description: 'A deadlift variation focusing on the hip hinge with minimal knee bend to primarily target the hamstrings and glutes.',
        videoUrl: 'https://www.youtube.com/embed/2z8JmcrW-As', muscleGroups: ['Hamstrings', 'Glutes', 'Erector Spinae'],
        sets: [
          { id: 'ogcb-d2-ex2-s1', exerciseId: 'ogcb-d2-ex2', targetReps: '8-12' },
          { id: 'ogcb-d2-ex2-s2', exerciseId: 'ogcb-d2-ex2', targetReps: '8-12' },
          { id: 'ogcb-d2-ex2-s3', exerciseId: 'ogcb-d2-ex2', targetReps: '8-12' },
        ],
      },
      {
        id: 'ogcb-d2-ex3', name: 'Leg Press', targetWeight: '180 lbs / 90 lbs', unit: 'reps',
        description: 'A machine-based exercise where you press a weighted platform away with your feet. Great for building leg mass with less strain on the back.',
        videoUrl: 'https://www.youtube.com/embed/s8-89_iT_aQ', muscleGroups: ['Quadriceps', 'Glutes', 'Hamstrings'],
        sets: [
          { id: 'ogcb-d2-ex3-s1', exerciseId: 'ogcb-d2-ex3', targetReps: '10-15' },
          { id: 'ogcb-d2-ex3-s2', exerciseId: 'ogcb-d2-ex3', targetReps: '10-15' },
          { id: 'ogcb-d2-ex3-s3', exerciseId: 'ogcb-d2-ex3', targetReps: '10-15' },
        ],
      },
      {
        id: 'ogcb-d2-ex4', name: 'Leg Extensions', targetWeight: '40 lbs / 20 lbs', unit: 'reps',
        description: 'An isolation machine exercise that specifically targets the quadriceps muscles.',
        videoUrl: 'https://www.youtube.com/embed/YyvSfVjQeL0', muscleGroups: ['Quadriceps'],
        sets: [
          { id: 'ogcb-d2-ex4-s1', exerciseId: 'ogcb-d2-ex4', targetReps: '12-15' },
          { id: 'ogcb-d2-ex4-s2', exerciseId: 'ogcb-d2-ex4', targetReps: '12-15' },
          { id: 'ogcb-d2-ex4-s3', exerciseId: 'ogcb-d2-ex4', targetReps: '12-15' },
        ],
      },
      {
        id: 'ogcb-d2-ex5', name: 'Leg Curls (Lying or Seated)', targetWeight: '40 lbs / 20 lbs', unit: 'reps',
        description: 'An isolation machine exercise that targets the hamstrings. Can be performed either lying face down or seated.',
        videoUrl: 'https://www.youtube.com/embed/1Tq3QdYUuHs', muscleGroups: ['Hamstrings'],
        sets: [
          { id: 'ogcb-d2-ex5-s1', exerciseId: 'ogcb-d2-ex5', targetReps: '12-15' },
          { id: 'ogcb-d2-ex5-s2', exerciseId: 'ogcb-d2-ex5', targetReps: '12-15' },
          { id: 'ogcb-d2-ex5-s3', exerciseId: 'ogcb-d2-ex5', targetReps: '12-15' },
        ],
      },
      {
        id: 'ogcb-d2-ex6', name: 'Standing Calf Raises', targetWeight: '45 lbs / 25 lbs', unit: 'reps',
        description: 'An isolation exercise for the larger gastrocnemius muscle of the calf. Can be done on a machine or with free weights.',
        videoUrl: 'https://www.youtube.com/embed/Jfl_g_h_AnA', muscleGroups: ['Gastrocnemius', 'Soleus'],
        sets: [
          { id: 'ogcb-d2-ex6-s1', exerciseId: 'ogcb-d2-ex6', targetReps: '15-20' },
          { id: 'ogcb-d2-ex6-s2', exerciseId: 'ogcb-d2-ex6', targetReps: '15-20' },
          { id: 'ogcb-d2-ex6-s3', exerciseId: 'ogcb-d2-ex6', targetReps: '15-20' },
        ],
      },
      {
        id: 'ogcb-d2-ex7', name: 'Core: Hanging Leg Raises (or Lying Leg Raises)', targetWeight: 'Bodyweight', unit: 'reps', isCore: true,
        description: 'A more advanced version of the hanging knee raise where you keep your legs straight, increasing the difficulty.',
        videoUrl: 'https://www.youtube.com/embed/Pr1ieGZ5atk', muscleGroups: ['Lower Rectus Abdominis', 'Hip Flexors'],
        sets: [
          { id: 'ogcb-d2-ex7-s1', exerciseId: 'ogcb-d2-ex7', targetReps: '15-20' },
          { id: 'ogcb-d2-ex7-s2', exerciseId: 'ogcb-d2-ex7', targetReps: '15-20' },
          { id: 'ogcb-d2-ex7-s3', exerciseId: 'ogcb-d2-ex7', targetReps: '15-20' },
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
        id: 'ogcb-d3-ex1', name: 'Pull-Ups', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'A bodyweight exercise where you hang from a bar and pull yourself up until your chin is over it. Excellent for building back width.',
        videoUrl: 'https://www.youtube.com/embed/e_5z3A4D6Fk', muscleGroups: ['Latissimus Dorsi', 'Biceps', 'Rhomboids'],
        sets: [
          { id: 'ogcb-d3-ex1-s1', exerciseId: 'ogcb-d3-ex1', targetReps: 'To Failure (or 6-10)' },
          { id: 'ogcb-d3-ex1-s2', exerciseId: 'ogcb-d3-ex1', targetReps: 'To Failure (or 6-10)' },
          { id: 'ogcb-d3-ex1-s3', exerciseId: 'ogcb-d3-ex1', targetReps: 'To Failure (or 6-10)' },
        ],
      },
      {
        id: 'ogcb-d3-ex2', name: 'Bent-Over Barbell Rows', targetWeight: '85 lbs / 45 lbs', unit: 'reps',
        description: 'A compound exercise where you hinge at the hips and pull a barbell towards your lower chest, building back thickness.',
        videoUrl: 'https://www.youtube.com/embed/vT2GjY_Umpw', muscleGroups: ['Latissimus Dorsi', 'Rhomboids', 'Traps', 'Biceps'],
        sets: [
          { id: 'ogcb-d3-ex2-s1', exerciseId: 'ogcb-d3-ex2', targetReps: '8-12' },
          { id: 'ogcb-d3-ex2-s2', exerciseId: 'ogcb-d3-ex2', targetReps: '8-12' },
          { id: 'ogcb-d3-ex2-s3', exerciseId: 'ogcb-d3-ex2', targetReps: '8-12' },
        ],
      },
      {
        id: 'ogcb-d3-ex3', name: 'Lat Pulldowns', targetWeight: '70 lbs / 40 lbs', unit: 'reps',
        description: 'A machine exercise that simulates a pull-up. Great for targeting the lats and building back width.',
        videoUrl: 'https://www.youtube.com/embed/0oe_dj_G9oU', muscleGroups: ['Latissimus Dorsi', 'Biceps'],
        sets: [
          { id: 'ogcb-d3-ex3-s1', exerciseId: 'ogcb-d3-ex3', targetReps: '10-15' },
          { id: 'ogcb-d3-ex3-s2', exerciseId: 'ogcb-d3-ex3', targetReps: '10-15' },
          { id: 'ogcb-d3-ex3-s3', exerciseId: 'ogcb-d3-ex3', targetReps: '10-15' },
        ],
      },
      {
        id: 'ogcb-d3-ex4', name: 'Inverted Rows', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'A bodyweight rowing exercise where you lie under a fixed bar and pull your chest up to it. A great precursor to pull-ups.',
        videoUrl: 'https://www.youtube.com/embed/hXTc1mDn2yY', muscleGroups: ['Rhomboids', 'Lats', 'Biceps', 'Posterior Deltoids'],
        sets: [
          { id: 'ogcb-d3-ex4-s1', exerciseId: 'ogcb-d3-ex4', targetReps: '10-15' },
          { id: 'ogcb-d3-ex4-s2', exerciseId: 'ogcb-d3-ex4', targetReps: '10-15' },
          { id: 'ogcb-d3-ex4-s3', exerciseId: 'ogcb-d3-ex4', targetReps: '10-15' },
        ],
      },
      {
        id: 'ogcb-d3-ex5', name: 'Chin-Ups', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'Similar to pull-ups but with an underhand (supinated) grip, which increases bicep involvement.',
        videoUrl: 'https://www.youtube.com/embed/b-2tM2n_p0M', muscleGroups: ['Latissimus Dorsi', 'Biceps'],
        sets: [
          { id: 'ogcb-d3-ex5-s1', exerciseId: 'ogcb-d3-ex5', targetReps: 'To Failure (or 6-10)' },
          { id: 'ogcb-d3-ex5-s2', exerciseId: 'ogcb-d3-ex5', targetReps: 'To Failure (or 6-10)' },
          { id: 'ogcb-d3-ex5-s3', exerciseId: 'ogcb-d3-ex5', targetReps: 'To Failure (or 6-10)' },
        ],
      },
      {
        id: 'ogcb-d3-ex6', name: 'Dumbbell Bicep Curls', targetWeight: '20 lbs / 10 lbs', unit: 'reps',
        description: 'The dumbbell version of the bicep curl, allowing for supination (twisting the wrist) to fully engage the bicep peak.',
        videoUrl: 'https://www.youtube.com/embed/yTWO2th-RIY', muscleGroups: ['Biceps Brachii'],
        sets: [
          { id: 'ogcb-d3-ex6-s1', exerciseId: 'ogcb-d3-ex6', targetReps: '10-15' },
          { id: 'ogcb-d3-ex6-s2', exerciseId: 'ogcb-d3-ex6', targetReps: '10-15' },
          { id: 'ogcb-d3-ex6-s3', exerciseId: 'ogcb-d3-ex6', targetReps: '10-15' },
        ],
      },
      {
        id: 'ogcb-d3-ex7', name: 'Face Pulls', targetWeight: '20 lbs / 10 lbs', unit: 'reps',
        description: 'A crucial exercise for shoulder health, targeting the rear deltoids and upper back muscles using a rope attachment on a cable machine.',
        videoUrl: 'https://www.youtube.com/embed/eIq5CB9wyoE', muscleGroups: ['Posterior Deltoids', 'Rhomboids', 'Traps'],
        sets: [
          { id: 'ogcb-d3-ex7-s1', exerciseId: 'ogcb-d3-ex7', targetReps: '15-20' },
          { id: 'ogcb-d3-ex7-s2', exerciseId: 'ogcb-d3-ex7', targetReps: '15-20' },
          { id: 'ogcb-d3-ex7-s3', exerciseId: 'ogcb-d3-ex7', targetReps: '15-20' },
        ],
      },
      {
        id: 'ogcb-d3-ex8', name: 'Core: Russian Twists', targetWeight: 'Bodyweight or 10 lbs / 5 lbs', unit: 'reps', isCore: true,
        description: 'A seated core exercise that targets the obliques by twisting your torso from side to side, often with a weight.',
        videoUrl: 'https://www.youtube.com/embed/wkD8rjkodUI', muscleGroups: ['Obliques', 'Rectus Abdominis'],
        sets: [
          { id: 'ogcb-d3-ex8-s1', exerciseId: 'ogcb-d3-ex8', targetReps: '15-20 per side' },
          { id: 'ogcb-d3-ex8-s2', exerciseId: 'ogcb-d3-ex8', targetReps: '15-20 per side' },
          { id: 'ogcb-d3-ex8-s3', exerciseId: 'ogcb-d3-ex8', targetReps: '15-20 per side' },
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
          { id: 'ogcb-d4-ex1-pistol-s1', exerciseId: 'ogcb-d4-ex1-pistol', targetReps: '5-8 per leg' },
          { id: 'ogcb-d4-ex1-pistol-s2', exerciseId: 'ogcb-d4-ex1-pistol', targetReps: '5-8 per leg' },
          { id: 'ogcb-d4-ex1-pistol-s3', exerciseId: 'ogcb-d4-ex1-pistol', targetReps: '5-8 per leg' },
        ],
        notes: 'Part of Calisthenics Strength Circuit.',
      },
      {
        id: 'ogcb-d4-ex1-archer', name: 'Archer Push-ups or Pseudo Planche Push-ups', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'Advanced pushing progression.',
        videoUrl: 'https://www.youtube.com/embed/hHXW1q4iJ08', muscleGroups: ['Chest', 'Shoulders', 'Triceps', 'Core'],
        sets: [
          { id: 'ogcb-d4-ex1-archer-s1', exerciseId: 'ogcb-d4-ex1-archer', targetReps: '5-8 per side/total' },
          { id: 'ogcb-d4-ex1-archer-s2', exerciseId: 'ogcb-d4-ex1-archer', targetReps: '5-8 per side/total' },
          { id: 'ogcb-d4-ex1-archer-s3', exerciseId: 'ogcb-d4-ex1-archer', targetReps: '5-8 per side/total' },
        ],
        notes: 'Part of Calisthenics Strength Circuit.',
      },
      {
        id: 'ogcb-d4-ex1-frontlever', name: 'Tuck Front Lever Holds (or progressions)', targetWeight: 'Bodyweight', unit: 's', isSkill: true,
        description: 'Isometric back and core strength. Progress from tuck front lever rows if needed.',
        videoUrl: 'https://www.youtube.com/embed/placeholder', muscleGroups: ['Lats', 'Core', 'Abs'],
        sets: [
          { id: 'ogcb-d4-ex1-frontlever-s1', exerciseId: 'ogcb-d4-ex1-frontlever', targetReps: '10-20', unit: 's' },
          { id: 'ogcb-d4-ex1-frontlever-s2', exerciseId: 'ogcb-d4-ex1-frontlever', targetReps: '10-20', unit: 's' },
          { id: 'ogcb-d4-ex1-frontlever-s3', exerciseId: 'ogcb-d4-ex1-frontlever', targetReps: '10-20', unit: 's' },
        ],
        notes: 'Part of Calisthenics Strength Circuit.',
      },
      {
        id: 'ogcb-d4-ex1-lsit', name: 'L-Sit Holds (or progressions)', targetWeight: 'Bodyweight', unit: 's', isCore: true, isSkill: true,
        description: 'Core compression and arm support strength. Progress from tucked L-sit if needed.',
        videoUrl: 'https://www.youtube.com/embed/PzAmVcjY2X8', muscleGroups: ['Core', 'Abs', 'Hip Flexors', 'Triceps'],
        sets: [
          { id: 'ogcb-d4-ex1-lsit-s1', exerciseId: 'ogcb-d4-ex1-lsit', targetReps: '10-20', unit: 's' },
          { id: 'ogcb-d4-ex1-lsit-s2', exerciseId: 'ogcb-d4-ex1-lsit', targetReps: '10-20', unit: 's' },
          { id: 'ogcb-d4-ex1-lsit-s3', exerciseId: 'ogcb-d4-ex1-lsit', targetReps: '10-20', unit: 's' },
        ],
        notes: 'Part of Calisthenics Strength Circuit.',
      },
      {
        id: 'ogcb-d4-core1', name: 'Core: Side Plank', targetWeight: 'Bodyweight', unit: 's', isCore: true,
        description: 'An isometric exercise where you support your body on one forearm, targeting the obliques and improving core stability.',
        videoUrl: 'https://www.youtube.com/embed/Z64142k_S84', muscleGroups: ['Obliques', 'Transverse Abdominis'],
        sets: [
          { id: 'ogcb-d4-core1-s1', exerciseId: 'ogcb-d4-core1', targetReps: '30-45 per side', unit: 's' },
          { id: 'ogcb-d4-core1-s2', exerciseId: 'ogcb-d4-core1', targetReps: '30-45 per side', unit: 's' },
          { id: 'ogcb-d4-core1-s3', exerciseId: 'ogcb-d4-core1', targetReps: '30-45 per side', unit: 's' },
        ],
        notes: 'Dedicated Core Work (Choose 2-3).',
      },
      {
        id: 'ogcb-d4-core2', name: 'Core: Bird Dog', targetWeight: 'Bodyweight', unit: 'reps', isCore: true,
        description: 'Core stability exercise. From all fours, extend opposite arm and leg, maintaining a flat back.',
        videoUrl: 'https://www.youtube.com/embed/wiFNA3sqjCA', muscleGroups: ['Core', 'Glutes', 'Lower Back', 'Shoulders'],
        sets: [
          { id: 'ogcb-d4-core2-s1', exerciseId: 'ogcb-d4-core2', targetReps: '10-12 per side' },
          { id: 'ogcb-d4-core2-s2', exerciseId: 'ogcb-d4-core2', targetReps: '10-12 per side' },
          { id: 'ogcb-d4-core2-s3', exerciseId: 'ogcb-d4-core2', targetReps: '10-12 per side' },
        ],
        notes: 'Dedicated Core Work (Choose 2-3).',
      },
      {
        id: 'ogcb-d4-core3', name: 'Core: Flutter Kicks', targetWeight: 'Bodyweight', unit: 's', isCore: true,
        description: 'Lying on your back with legs extended, you perform small, rapid up-and-down kicks, targeting the lower abs.',
        videoUrl: 'https://www.youtube.com/embed/ANVdMDa-dGo', muscleGroups: ['Lower Rectus Abdominis'],
        sets: [
          { id: 'ogcb-d4-core3-s1', exerciseId: 'ogcb-d4-core3', targetReps: '30-60', unit: 's' },
          { id: 'ogcb-d4-core3-s2', exerciseId: 'ogcb-d4-core3', targetReps: '30-60', unit: 's' },
          { id: 'ogcb-d4-core3-s3', exerciseId: 'ogcb-d4-core3', targetReps: '30-60', unit: 's' },
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
        id: 'ogcb-d5-ex1', name: 'Goblet Squats', targetWeight: '25 lbs / 15 lbs', unit: 'reps',
        description: 'A squat performed while holding a single dumbbell or kettlebell at chest level. Excellent for teaching proper squat form.',
        videoUrl: 'https://www.youtube.com/embed/MeW1_r32I3o', muscleGroups: ['Quadriceps', 'Glutes', 'Core'],
        sets: [
          { id: 'ogcb-d5-ex1-s1', exerciseId: 'ogcb-d5-ex1', targetReps: '12-15' },
          { id: 'ogcb-d5-ex1-s2', exerciseId: 'ogcb-d5-ex1', targetReps: '12-15' },
          { id: 'ogcb-d5-ex1-s3', exerciseId: 'ogcb-d5-ex1', targetReps: '12-15' },
        ],
      },
      {
        id: 'ogcb-d5-ex2', name: 'Single-Arm Dumbbell Rows', targetWeight: '25 lbs / 15 lbs', unit: 'reps',
        description: 'A unilateral rowing exercise, typically performed with one knee and hand on a bench, which helps isolate the lats.',
        videoUrl: 'https://www.youtube.com/embed/pYcpY20QaE8', muscleGroups: ['Latissimus Dorsi', 'Rhomboids', 'Biceps'],
        sets: [
          { id: 'ogcb-d5-ex2-s1', exerciseId: 'ogcb-d5-ex2', targetReps: '10-12 per arm' },
          { id: 'ogcb-d5-ex2-s2', exerciseId: 'ogcb-d5-ex2', targetReps: '10-12 per arm' },
          { id: 'ogcb-d5-ex2-s3', exerciseId: 'ogcb-d5-ex2', targetReps: '10-12 per arm' },
        ],
      },
      {
        id: 'ogcb-d5-ex3', name: 'Push-up Progression (e.g., Kneeling, Standard, or Incline)', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'Focus on good form, stop before true muscle failure.',
        videoUrl: 'https://www.youtube.com/embed/IODxDxX7oi4', muscleGroups: ['Chest', 'Triceps', 'Shoulders'],
        sets: [
          { id: 'ogcb-d5-ex3-s1', exerciseId: 'ogcb-d5-ex3', targetReps: 'Comfortable Failure' },
          { id: 'ogcb-d5-ex3-s2', exerciseId: 'ogcb-d5-ex3', targetReps: 'Comfortable Failure' },
          { id: 'ogcb-d5-ex3-s3', exerciseId: 'ogcb-d5-ex3', targetReps: 'Comfortable Failure' },
        ],
      },
      {
        id: 'ogcb-d5-ex4', name: 'Inverted Rows (Bodyweight Rows)', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'Controlled bodyweight back exercise.',
        videoUrl: 'https://www.youtube.com/embed/hXTc1mDn2yY', muscleGroups: ['Upper Back', 'Lats', 'Biceps'],
        sets: [
          { id: 'ogcb-d5-ex4-s1', exerciseId: 'ogcb-d5-ex4', targetReps: '10-15' },
          { id: 'ogcb-d5-ex4-s2', exerciseId: 'ogcb-d5-ex4', targetReps: '10-15' },
          { id: 'ogcb-d5-ex4-s3', exerciseId: 'ogcb-d5-ex4', targetReps: '10-15' },
        ],
      },
      {
        id: 'ogcb-d5-ex5', name: 'Core: Dead Bug', targetWeight: 'Bodyweight', unit: 'reps', isCore: true,
        description: 'Core stability and anti-extension.',
        videoUrl: 'https://www.youtube.com/embed/g_BYB4vAoqs', muscleGroups: ['Core', 'Abs'],
        sets: [
          { id: 'ogcb-d5-ex5-s1', exerciseId: 'ogcb-d5-ex5', targetReps: '10-12 per side' },
          { id: 'ogcb-d5-ex5-s2', exerciseId: 'ogcb-d5-ex5', targetReps: '10-12 per side' },
          { id: 'ogcb-d5-ex5-s3', exerciseId: 'ogcb-d5-ex5', targetReps: '10-12 per side' },
        ],
      },
      {
        id: 'ogcb-d5-ex6', name: 'Flexibility & Mobility Session', targetWeight: 'Bodyweight', unit: 'min', isActivity: true, isMobility: true, isStretch: true,
        description: '10-15 minutes on static stretches, focusing on areas that feel tight (hips, hamstrings, chest, shoulders) and/or foam rolling.',
        videoUrl: 'https://www.youtube.com/embed/Sj_N63D0Zck', muscleGroups: ['Full Body'],
        sets: [{ id: 'ogcb-d5-ex6-s1', exerciseId: 'ogcb-d5-ex6', targetReps: '10-15', unit: 'min' }],
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
        sets: [{ id: 'ogcb-d6-ex1-s1', exerciseId: 'ogcb-d6-ex1', targetReps: '90', unit: 'min' }],
      },
    ],
  },
  {
    id: 'ogcb-day7',
    dayName: 'Sunday',
    title: 'Complete Rest',
    mapsToActualDayOfWeek: 0,
    isRecovery: true,
    notes: 'Allow your body to fully recover and rebuild. Focus on good nutrition and hydration.',
    exercises: [
      {
        id: 'ogcb-d7-ex1', name: 'Rest Day Activities', targetWeight: 'N/A', unit: 'min', isActivity: true, isRecovery: true,
        description: 'Complete rest from intense training. Light activities like walking are okay.',
        videoUrl: 'https://www.youtube.com/embed/placeholder', muscleGroups: ['N/A'],
        sets: [{ id: 'ogcb-d7-ex1-s1', exerciseId: 'ogcb-d7-ex1', targetReps: 'Full Day' }],
      },
    ],
  },
];

const jeffNippardPlan: WeeklyPlan = [
  {
    id: 'jn-day1', dayName: 'Monday', title: 'PUSH (Chest / Shoulders / Triceps)', mapsToActualDayOfWeek: 1,
    exercises: [
      {
        id: 'jn-mon-ex1', name: 'Ring or Decline Push-Ups', description: 'Advanced bodyweight push-up variation targeting the upper chest and shoulders.', videoUrl: 'https://www.youtube.com/embed/Pkj8LLRsoDw', muscleGroups: ['Chest', 'Shoulders', 'Triceps'], sets: [
          { id: 'jn-d1e1s1', exerciseId: 'jn-mon-ex1', targetReps: '8-12' }, { id: 'jn-d1e1s2', exerciseId: 'jn-mon-ex1', targetReps: '8-12' }, { id: 'jn-d1e1s3', exerciseId: 'jn-mon-ex1', targetReps: '8-12' }, { id: 'jn-d1e1s4', exerciseId: 'jn-mon-ex1', targetReps: '8-12' }
        ]
      },
      {
        id: 'jn-d1e2s-dips', name: 'Chest Dips', description: 'Performed on parallel bars, leaning your torso forward emphasizes the chest muscles, particularly the lower chest.', videoUrl: 'https://www.youtube.com/embed/c3ZGl4pAWiM', muscleGroups: ['Lower Pectoralis', 'Triceps', 'Deltoids'], sets: [
          { id: 'jn-d1e2s1', exerciseId: 'jn-d1e2s-dips', targetReps: '6-10' }, { id: 'jn-d1e2s2', exerciseId: 'jn-d1e2s-dips', targetReps: '6-10' }, { id: 'jn-d1e2s3', exerciseId: 'jn-d1e2s-dips', targetReps: '6-10' }
        ]
      },
      {
        id: 'ogcb-d1-ex1', name: 'Machine Chest Press', description: 'A seated machine exercise that mimics the bench press in a safer, more controlled manner. Great for beginners.', videoUrl: 'https://www.youtube.com/embed/Xa9-6pYk0_U', muscleGroups: ['Pectoralis Major', 'Triceps', 'Deltoids'], sets: [
          { id: 'jn-d1e3s1', exerciseId: 'ogcb-d1-ex1', targetReps: '8-12' }, { id: 'jn-d1e3s2', exerciseId: 'ogcb-d1-ex1', targetReps: '8-12' }, { id: 'jn-d1e3s3', exerciseId: 'ogcb-d1-ex1', targetReps: '8-12' }, { id: 'jn-d1e3s4', exerciseId: 'ogcb-d1-ex1', targetReps: '8-12' }
        ]
      },
      {
        id: 'jn-mon-ex4', name: 'Machine Shoulder Press', description: 'Machine-based compound movement for shoulder development.', videoUrl: 'https://www.youtube.com/embed/b_1hO-D9I-M', muscleGroups: ['Shoulders', 'Triceps'], sets: [
          { id: 'jn-d1e4s1', exerciseId: 'jn-mon-ex4', targetReps: '8-12' }, { id: 'jn-d1e4s2', exerciseId: 'jn-mon-ex4', targetReps: '8-12' }, { id: 'jn-d1e4s3', exerciseId: 'jn-mon-ex4', targetReps: '8-12' }
        ]
      },
      {
        id: 'jn-mon-ex5', name: 'Bent-over Cable Fly', description: 'Isolation exercise for the chest, providing constant tension through the movement.', videoUrl: 'https://www.youtube.com/embed/Iwe6AmxVf7o', muscleGroups: ['Chest'], sets: [
          { id: 'jn-d1e5s1', exerciseId: 'jn-mon-ex5', targetReps: '12-15' }, { id: 'jn-d1e5s2', exerciseId: 'jn-mon-ex5', targetReps: '12-15' }, { id: 'jn-d1e5s3', exerciseId: 'jn-mon-ex5', targetReps: '12-15' }
        ]
      },
      {
        id: 'lib-tri-pushdown-bar', name: 'Cable Triceps Pushdowns (Bar)', description: 'Triceps isolation exercise using a cable machine.', videoUrl: 'https://www.youtube.com/embed/2-LAMcpzODU', muscleGroups: ['Triceps'], sets: [
          { id: 'jn-d1e6s1', exerciseId: 'lib-tri-pushdown-bar', targetReps: '10-15' }, { id: 'jn-d1e6s2', exerciseId: 'lib-tri-pushdown-bar', targetReps: '10-15' }, { id: 'jn-d1e6s3', exerciseId: 'lib-tri-pushdown-bar', targetReps: '10-15' }
        ]
      },
    ]
  },
  {
    id: 'jn-day2', dayName: 'Tuesday', title: 'PULL (Back / Biceps)', mapsToActualDayOfWeek: 2,
    exercises: [
      {
        id: 'ppl-tue-ex1-v2', name: 'Pull-Ups', description: 'A bodyweight exercise where you hang from a bar and pull yourself up until your chin is over it. Excellent for building back width.', videoUrl: 'https://www.youtube.com/embed/e_5z3A4D6Fk', muscleGroups: ['Latissimus Dorsi', 'Biceps', 'Rhomboids'], sets: [
          { id: 'jn-d2e1s1', exerciseId: 'ppl-tue-ex1-v2', targetReps: '6-10' }, { id: 'jn-d2e1s2', exerciseId: 'ppl-tue-ex1-v2', targetReps: '6-10' }, { id: 'jn-d2e1s3', exerciseId: 'ppl-tue-ex1-v2', targetReps: '6-10' }, { id: 'jn-d2e1s4', exerciseId: 'ppl-tue-ex1-v2', targetReps: '6-10' }
        ]
      },
      {
        id: 'ppl-tue-ex3-v2', name: 'Inverted Rows', description: 'Bodyweight exercise for back thickness. Adjust body angle to change difficulty.', videoUrl: 'https://www.youtube.com/embed/hXTc1mDn2yY', muscleGroups: ['Upper Back', 'Lats', 'Biceps'], sets: [
          { id: 'jn-d2e2s1', exerciseId: 'ppl-tue-ex3-v2', targetReps: '8-12' }, { id: 'jn-d2e2s2', exerciseId: 'ppl-tue-ex3-v2', targetReps: '8-12' }, { id: 'jn-d2e2s3', exerciseId: 'ppl-tue-ex3-v2', targetReps: '8-12' }
        ]
      },
      {
        id: 'ppl-tue-ex2', name: 'Seated Cable Rows', description: 'A machine-based rowing exercise that targets the mid-back and is excellent for improving posture.', videoUrl: 'https://www.youtube.com/embed/GZbfZ033f74', muscleGroups: ['Rhomboids', 'Latissimus Dorsi', 'Biceps'], sets: [
          { id: 'jn-d2e3s1', exerciseId: 'ppl-tue-ex2', targetReps: '10-12' }, { id: 'jn-d2e3s2', exerciseId: 'ppl-tue-ex2', targetReps: '10-12' }, { id: 'jn-d2e3s3', exerciseId: 'ppl-tue-ex2', targetReps: '10-12' }
        ]
      },
      {
        id: 'ppl-fri-ex2-v2', name: 'Lat Pulldowns', description: 'A machine exercise that simulates a pull-up. Great for targeting the lats and building back width.', videoUrl: 'https://www.youtube.com/embed/0oe_dj_G9oU', muscleGroups: ['Latissimus Dorsi', 'Biceps'], sets: [
          { id: 'jn-d2e4s1', exerciseId: 'ppl-fri-ex2-v2', targetReps: '8-12' }, { id: 'jn-d2e4s2', exerciseId: 'ppl-fri-ex2-v2', targetReps: '8-12' }, { id: 'jn-d2e4s3', exerciseId: 'ppl-fri-ex2-v2', targetReps: '8-12' }
        ]
      },
      {
        id: 'jn-tue-ex5', name: 'Dual Cable Biceps Curl', description: 'Cable-based biceps curl that provides constant tension.', videoUrl: 'https://www.youtube.com/embed/NFzTWp2qpiE', muscleGroups: ['Biceps'], sets: [
          { id: 'jn-d2e5s1', exerciseId: 'jn-tue-ex5', targetReps: '10-12' }, { id: 'jn-d2e5s2', exerciseId: 'jn-tue-ex5', targetReps: '10-12' }, { id: 'jn-d2e5s3', exerciseId: 'jn-tue-ex5', targetReps: '10-12' }
        ]
      },
      {
        id: 'lib-hammer-curl', name: 'Hammer Curls', description: 'A bicep curl with a neutral (hammer) grip. This targets the brachialis and brachioradialis in addition to the biceps, building arm thickness.', videoUrl: 'https://www.youtube.com/embed/zC3nLHv29AI', muscleGroups: ['Biceps', 'Brachialis', 'Brachioradialis'], sets: [
          { id: 'jn-d2e6s1', exerciseId: 'lib-hammer-curl', targetReps: '10-12' }, { id: 'jn-d2e6s2', exerciseId: 'lib-hammer-curl', targetReps: '10-12' }
        ], notes: 'Optional'
      },
    ]
  },
  {
    id: 'jn-day3', dayName: 'Wednesday', title: 'LEGS + CORE', mapsToActualDayOfWeek: 3,
    exercises: [
      {
        id: 'lib-hack-squat-v2', name: 'Pendulum or Hack Squat', description: 'Machine squat variation to emphasize quadriceps development.', videoUrl: 'https://www.youtube.com/embed/0tn5_9DBA7g', muscleGroups: ['Quadriceps', 'Glutes'], sets: [
          { id: 'jn-d3e1s1', exerciseId: 'lib-hack-squat-v2', targetReps: '8-10' }, { id: 'jn-d3e1s2', exerciseId: 'lib-hack-squat-v2', targetReps: '8-10' }, { id: 'jn-d3e1s3', exerciseId: 'lib-hack-squat-v2', targetReps: '8-10' }
        ]
      },
      {
        id: 'ppl-wed-ex1-v2', name: 'Leg Press', description: 'A machine-based exercise where you press a weighted platform away with your feet. Great for building leg mass with less strain on the back.', videoUrl: 'https://www.youtube.com/embed/s8-89_iT_aQ', muscleGroups: ['Quadriceps', 'Glutes', 'Hamstrings'], sets: [
          { id: 'jn-d3e2s1', exerciseId: 'ppl-wed-ex1-v2', targetReps: '12-15' }, { id: 'jn-d3e2s2', exerciseId: 'ppl-wed-ex1-v2', targetReps: '12-15' }, { id: 'jn-d3e2s3', exerciseId: 'ppl-wed-ex1-v2', targetReps: '12-15' }
        ]
      },
      {
        id: 'ppl-sat-ex3-v2', name: 'Leg Extensions', description: 'An isolation machine exercise that specifically targets the quadriceps muscles.', videoUrl: 'https://www.youtube.com/embed/YyvSfVjQeL0', muscleGroups: ['Quadriceps'], sets: [
          { id: 'jn-d3e3s1', exerciseId: 'ppl-sat-ex3-v2', targetReps: '12-15' }, { id: 'jn-d3e3s2', exerciseId: 'ppl-sat-ex3-v2', targetReps: '12-15' }, { id: 'jn-d3e3s3', exerciseId: 'ppl-sat-ex3-v2', targetReps: '12-15' }, { id: 'jn-d3e3s4', exerciseId: 'ppl-sat-ex3-v2', targetReps: '12-15' }
        ]
      },
      {
        id: 'ppl-wed-ex3-v2', name: 'Leg Curls (Lying or Seated)', description: 'An isolation machine exercise that targets the hamstrings. Can be performed either lying face down or seated.', videoUrl: 'https://www.youtube.com/embed/1Tq3QdYUuHs', muscleGroups: ['Hamstrings'], sets: [
          { id: 'jn-d3e4s1', exerciseId: 'ppl-wed-ex3-v2', targetReps: '10-12' }, { id: 'jn-d3e4s2', exerciseId: 'ppl-wed-ex3-v2', targetReps: '10-12' }, { id: 'jn-d3e4s3', exerciseId: 'ppl-wed-ex3-v2', targetReps: '10-12' }, { id: 'jn-d3e4s4', exerciseId: 'ppl-wed-ex3-v2', targetReps: '10-12' }
        ]
      },
      {
        id: 'jn-wed-ex5', name: 'Calf Press on Leg Press', description: 'Calf isolation using the leg press machine for heavy load.', videoUrl: 'https://www.youtube.com/embed/zDCiA-o-2s4', muscleGroups: ['Calves'], sets: [
          { id: 'jn-d3e5s1', exerciseId: 'jn-wed-ex5', targetReps: '15-20' }, { id: 'jn-d3e5s2', exerciseId: 'jn-wed-ex5', targetReps: '15-20' }, { id: 'jn-d3e5s3', exerciseId: 'jn-wed-ex5', targetReps: '15-20' }
        ]
      },
      {
        id: 'ppl-tue-ex6-v2', name: 'Hanging Leg Raises', isCore: true, description: 'A more advanced version of the hanging knee raise where you keep your legs straight, increasing the difficulty.', videoUrl: 'https://www.youtube.com/embed/Pr1ieGZ5atk', muscleGroups: ['Lower Rectus Abdominis', 'Core'], sets: [
          { id: 'jn-d3e6s1', exerciseId: 'ppl-tue-ex6-v2', targetReps: '12-15' }, { id: 'jn-d3e6s2', exerciseId: 'ppl-tue-ex6-v2', targetReps: '12-15' }, { id: 'jn-d3e6s3', exerciseId: 'ppl-tue-ex6-v2', targetReps: '12-15' }
        ]
      },
      {
        id: 'ppl-mon-ex6-v2', name: 'Plank', isCore: true, unit: 's', description: 'An isometric core exercise where you hold a push-up-like position on your forearms, maintaining a straight line from head to heels.', videoUrl: 'https://www.youtube.com/embed/pDafg-Bv-s8', muscleGroups: ['Rectus Abdominis, Transverse Abdominis, Obliques'], sets: [
          { id: 'jn-d3e7s1', exerciseId: 'ppl-mon-ex6-v2', targetReps: '45-60', unit: 's' }, { id: 'jn-d3e7s2', exerciseId: 'ppl-mon-ex6-v2', targetReps: '45-60', unit: 's' }, { id: 'jn-d3e7s3', exerciseId: 'ppl-mon-ex6-v2', targetReps: '45-60', unit: 's' }
        ]
      },
    ]
  },
  {
    id: 'jn-day4', dayName: 'Thursday', title: 'REST', isRecovery: true, mapsToActualDayOfWeek: 4,
    exercises: [{ id: 'jn-thu-rest', name: 'Rest Day', isActivity: true, description: 'Focus on recovery, nutrition, and hydration.', muscleGroups: ['N/A'], sets: [{ id: 'jn-d4-rest-s1', exerciseId: 'jn-thu-rest', targetReps: 'Full day' }] }]
  },
  {
    id: 'jn-day5', dayName: 'Friday', title: 'UPPER BODY (Calisthenics Focus)', mapsToActualDayOfWeek: 5,
    exercises: [
      {
        id: 'jn-fri-ex1', name: 'Muscle-Ups (or Pull-Up + Dip Superset)', isSkill: true, description: 'Advanced calisthenics skill. If not possible, superset one pull-up with one dip.', videoUrl: 'https://www.youtube.com/embed/tW5fA2E0y-0', muscleGroups: ['Lats', 'Biceps', 'Chest', 'Triceps', 'Shoulders'], sets: [
          { id: 'jn-d5e1s1', exerciseId: 'jn-fri-ex1', targetReps: '3-6' }, { id: 'jn-d5e1s2', exerciseId: 'jn-fri-ex1', targetReps: '3-6' }, { id: 'jn-d5e1s3', exerciseId: 'jn-fri-ex1', targetReps: '3-6' }
        ]
      },
      {
        id: 'ogcb-d4-ex1-archer-v2', name: 'Archer Push-Ups', description: 'Unilateral push-up variation to build single-arm strength.', videoUrl: 'https://www.youtube.com/embed/hHXW1q4iJ08', muscleGroups: ['Chest', 'Shoulders', 'Triceps', 'Core'], sets: [
          { id: 'jn-d5e2s1', exerciseId: 'ogcb-d4-ex1-archer-v2', targetReps: '6-8 per side' }, { id: 'jn-d5e2s2', exerciseId: 'ogcb-d4-ex1-archer-v2', targetReps: '6-8 per side' }, { id: 'jn-d5e2s3', exerciseId: 'ogcb-d4-ex1-archer-v2', targetReps: '6-8 per side' }
        ]
      },
      {
        id: 'cal-wed-decline-pushups-v2', name: 'Feet-Elevated Push-Ups', description: 'Push-up with feet elevated to increase difficulty and target the upper chest.', videoUrl: 'https://www.youtube.com/embed/Pkj8LLRsoDw', muscleGroups: ['Chest (Upper)', 'Shoulders', 'Triceps'], sets: [
          { id: 'jn-d5e3s1', exerciseId: 'cal-wed-decline-pushups-v2', targetReps: '10-12' }, { id: 'jn-d5e3s2', exerciseId: 'cal-wed-decline-pushups-v2', targetReps: '10-12' }, { id: 'jn-d5e3s3', exerciseId: 'cal-wed-decline-pushups-v2', targetReps: '10-12' }
        ]
      },
      {
        id: 'ppl-tue-ex3-v3', name: 'Bodyweight Rows', description: 'Same as Inverted Rows. A fundamental bodyweight pulling exercise.', videoUrl: 'https://www.youtube.com/embed/hXTc1mDn2yY', muscleGroups: ['Upper Back', 'Lats', 'Biceps'], sets: [
          { id: 'jn-d5e4s1', exerciseId: 'ppl-tue-ex3-v3', targetReps: '10-12' }, { id: 'jn-d5e4s2', exerciseId: 'ppl-tue-ex3-v3', targetReps: '10-12' }, { id: 'jn-d5e4s3', exerciseId: 'ppl-tue-ex3-v3', targetReps: '10-12' }, { id: 'jn-d5e4s4', exerciseId: 'ppl-tue-ex3-v3', targetReps: '10-12' }
        ]
      },
      {
        id: 'cal-mon-skill-hs-v2', name: 'Handstand Push-Ups', isSkill: true, unit: 'reps', description: 'An advanced calisthenics exercise that involves doing a push-up while in a handstand position against a wall. The ultimate bodyweight shoulder exercise.', videoUrl: 'https://www.youtube.com/embed/d_M-v-g_FFI', muscleGroups: ['Deltoids', 'Triceps', 'Traps'], sets: [
          { id: 'jn-d5e5s1', exerciseId: 'cal-mon-skill-hs-v2', targetReps: 'To Failure' }, { id: 'jn-d5e5s2', exerciseId: 'cal-mon-skill-hs-v2', targetReps: 'To Failure' }, { id: 'jn-d5e5s3', exerciseId: 'cal-mon-skill-hs-v2', targetReps: 'To Failure' }
        ]
      },
      {
        id: 'ppl-fri-ex6-v2', name: 'L-Sit Hold', isCore: true, isSkill: true, unit: 's', description: 'Advanced core compression exercise.', videoUrl: 'https://www.youtube.com/embed/PzAmVcjY2X8', muscleGroups: ['Core', 'Abs', 'Hip Flexors'], sets: [
          { id: 'jn-d5e6s1', exerciseId: 'ppl-fri-ex6-v2', targetReps: '20-30', unit: 's' }, { id: 'jn-d5e6s2', exerciseId: 'ppl-fri-ex6-v2', targetReps: '20-30', unit: 's' }, { id: 'jn-d5e6s3', exerciseId: 'ppl-fri-ex6-v2', targetReps: '20-30', unit: 's' }
        ]
      },
    ]
  },
  {
    id: 'jn-day6', dayName: 'Saturday', title: 'ARMS + SHOULDERS (Pump Day)', mapsToActualDayOfWeek: 6,
    exercises: [
      {
        id: 'jn-sat-ex1', name: 'Preacher Curls', description: 'Biceps isolation with a machine to enforce strict form.', videoUrl: 'https://www.youtube.com/embed/fIWP-FRFNU0', muscleGroups: ['Biceps Brachii'], sets: [
          { id: 'jn-d6e1s1', exerciseId: 'jn-sat-ex1', targetReps: '10-12' }, { id: 'jn-d6e1s2', exerciseId: 'jn-sat-ex1', targetReps: '10-12' }, { id: 'jn-d6e1s3', exerciseId: 'jn-sat-ex1', targetReps: '10-12' }
        ]
      },
      {
        id: 'ppl-mon-ex5-v2', name: 'Triceps Pushdowns (Rope)', description: 'A common triceps isolation exercise on a cable machine. A rope allows for greater range of motion, while a bar allows for heavier weight.', videoUrl: 'https://www.youtube.com/embed/2-LAMcpzODU', muscleGroups: ['Triceps Brachii'], sets: [
          { id: 'jn-d6e2s1', exerciseId: 'ppl-mon-ex5-v2', targetReps: '12-15' }, { id: 'jn-d6e2s2', exerciseId: 'ppl-mon-ex5-v2', targetReps: '12-15' }, { id: 'jn-d6e2s3', exerciseId: 'ppl-mon-ex5-v2', targetReps: '12-15' }
        ]
      },
      {
        id: 'jn-sat-ex3', name: 'Cable Lateral Raises', description: 'A lateral raise variation using a low cable pulley, which provides constant tension on the deltoid throughout the movement.', videoUrl: 'https://www.youtube.com/embed/p4l5gtoaH0M', muscleGroups: ['Lateral Deltoids'], sets: [
          { id: 'jn-d6e3s1', exerciseId: 'jn-sat-ex3', targetReps: '12-15' }, { id: 'jn-d6e3s2', exerciseId: 'jn-sat-ex3', targetReps: '12-15' }, { id: 'jn-d6e3s3', exerciseId: 'jn-sat-ex3', targetReps: '12-15' }
        ]
      },
      {
        id: 'jn-sat-ex4', name: 'Overhead Triceps Extensions', description: 'Can be done seated or standing with a dumbbell or cable. This exercise fully stretches the long head of the triceps.', videoUrl: 'https://www.youtube.com/embed/3_h-02AqPA4', muscleGroups: ['Triceps Brachii'], sets: [
          { id: 'jn-d6e4s1', exerciseId: 'jn-sat-ex4', targetReps: '10-12' }, { id: 'jn-d6e4s2', exerciseId: 'jn-sat-ex4', targetReps: '10-12' }, { id: 'jn-d6e4s3', exerciseId: 'jn-sat-ex4', targetReps: '10-12' }
        ]
      },
      {
        id: 'lib-reverse-pec-deck', name: 'Reverse Pec-Deck', description: 'A machine exercise that isolates the posterior deltoids and upper back muscles.', videoUrl: 'https://www.youtube.com/embed/5_HJm609L7g', muscleGroups: ['Posterior Deltoids', 'Rhomboids'], sets: [
          { id: 'jn-d6e5s1', exerciseId: 'lib-reverse-pec-deck', targetReps: '12-15' }, { id: 'jn-d6e5s2', exerciseId: 'lib-reverse-pec-deck', targetReps: '12-15' }, { id: 'jn-d6e5s3', exerciseId: 'lib-reverse-pec-deck', targetReps: '12-15' }
        ]
      },
      {
        id: 'jn-sat-ex6', name: 'Cable 21s (Biceps Finisher)', description: 'A high-volume finisher for biceps: 7 bottom-half reps, 7 top-half reps, 7 full reps.', videoUrl: 'https://www.youtube.com/embed/kG-A9Q926qA', muscleGroups: ['Biceps'], sets: [
          { id: 'jn-d6e6s1', exerciseId: 'jn-sat-ex6', targetReps: '21' }, { id: 'jn-d6e6s2', exerciseId: 'jn-sat-ex6', targetReps: '21' }
        ]
      },
    ]
  },
  {
    id: 'jn-day7', dayName: 'Sunday', title: 'REST', isRecovery: true, mapsToActualDayOfWeek: 0,
    exercises: [{ id: 'jn-sun-rest', name: 'Rest Day', isActivity: true, description: 'Focus on recovery, nutrition, and hydration.', muscleGroups: ['N/A'], sets: [{ id: 'jn-d7-rest-s1', exerciseId: 'jn-sun-rest', targetReps: 'Full day' }] }]
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
        id: 'lib-bp', name: 'Barbell Bench Press', targetWeight: '95 lbs / 45 lbs', unit: 'reps',
        description: 'Lie on a flat bench, pressing a barbell from your chest upwards until arms are fully extended. A foundational compound lift for upper body strength.',
        videoUrl: 'https://www.youtube.com/embed/rT7DgCr-3pg',
        muscleGroups: ['Pectoralis Major', 'Triceps', 'Anterior Deltoids'],
        sets: [{ id: 'lib-bp-s1', exerciseId: 'lib-bp', targetReps: '6-10' }, { id: 'lib-bp-s2', exerciseId: 'lib-bp', targetReps: '6-10' }, { id: 'lib-bp-s3', exerciseId: 'lib-bp', targetReps: '6-10' }, {id: 'lib-bp-s4', exerciseId: 'lib-bp', targetReps: '6-10' }],
      },
      {
        id: 'lib-incline-bp', name: 'Incline Barbell Press', targetWeight: '75 lbs / 35 lbs', unit: 'reps',
        description: 'Performed on a bench set at a 30-45 degree incline, this variation emphasizes the upper (clavicular) head of the pectoralis major.',
        videoUrl: 'https://www.youtube.com/embed/SrqOu55lrqg',
        muscleGroups: ['Upper Pectoralis', 'Anterior Deltoids', 'Triceps'],
        sets: [{ id: 'lib-incline-bp-s1', exerciseId: 'lib-incline-bp', targetReps: '8-12' }, { id: 'lib-incline-bp-s2', exerciseId: 'lib-incline-bp', targetReps: '8-12' }, { id: 'lib-incline-bp-s3', exerciseId: 'lib-incline-bp', targetReps: '8-12' }],
      },
      {
        id: 'lib-decline-bp', name: 'Decline Barbell Press', targetWeight: '85 lbs / 35 lbs', unit: 'reps',
        description: 'Executed on a decline bench, this movement targets the lower (sternocostal) head of the pectoralis major.',
        videoUrl: 'https://www.youtube.com/embed/LfyQBUKR8s4',
        muscleGroups: ['Lower Pectoralis', 'Triceps', 'Deltoids'],
        sets: [{ id: 'lib-decline-bp-s1', exerciseId: 'lib-decline-bp', targetReps: '8-12' }, { id: 'lib-decline-bp-s2', exerciseId: 'lib-decline-bp', targetReps: '8-12' }, { id: 'lib-decline-bp-s3', exerciseId: 'lib-decline-bp', targetReps: '8-12' }],
      },
      {
        id: 'lib-db-bp', name: 'Dumbbell Bench Press', targetWeight: '30 lbs / 15 lbs', unit: 'reps',
        description: 'Similar to the barbell version but using dumbbells, allowing for a greater range of motion and requiring more stabilization.',
        videoUrl: 'https://www.youtube.com/embed/VmB1G1K7v94',
        muscleGroups: ['Pectoralis Major', 'Triceps', 'Deltoids'],
        sets: [{ id: 'lib-db-bp-s1', exerciseId: 'lib-db-bp', targetReps: '8-12' }, { id: 'lib-db-bp-s2', exerciseId: 'lib-db-bp', targetReps: '8-12' }, { id: 'lib-db-bp-s3', exerciseId: 'lib-db-bp', targetReps: '8-12' }],
      },
      {
        id: 'lib-incline-db-bp', name: 'Incline Dumbbell Press', targetWeight: '25 lbs / 10 lbs', unit: 'reps',
        description: 'Using dumbbells on an incline bench to target the upper chest. The independent movement of dumbbells helps correct muscle imbalances.',
        videoUrl: 'https://www.youtube.com/embed/8iPEnn-ltC8',
        muscleGroups: ['Upper Pectoralis', 'Deltoids', 'Triceps'],
        sets: [{ id: 'lib-incline-db-bp-s1', exerciseId: 'lib-incline-db-bp', targetReps: '8-12' }, { id: 'lib-incline-db-bp-s2', exerciseId: 'lib-incline-db-bp', targetReps: '8-12' }, { id: 'lib-incline-db-bp-s3', exerciseId: 'lib-incline-db-bp', targetReps: '8-12' }],
      },
      {
        id: 'lib-decline-db-bp', name: 'Decline Dumbbell Press', targetWeight: '30 lbs / 15 lbs', unit: 'reps',
        description: 'Using dumbbells on a decline bench, this exercise targets the lower chest and allows for a deep stretch.',
        videoUrl: 'https://www.youtube.com/embed/Vd90yYt05_s',
        muscleGroups: ['Lower Pectoralis', 'Triceps', 'Deltoids'],
        sets: [{ id: 'lib-decline-db-bp-s1', exerciseId: 'lib-decline-db-bp', targetReps: '8-12' }, { id: 'lib-decline-db-bp-s2', exerciseId: 'lib-decline-db-bp', targetReps: '8-12' }, { id: 'lib-decline-db-bp-s3', exerciseId: 'lib-decline-db-bp', targetReps: '8-12' }],
      },
      {
        id: 'lib-db-flys', name: 'Dumbbell Flys', targetWeight: '15 lbs / 5 lbs', unit: 'reps',
        description: 'An isolation exercise on a flat bench. With a slight bend in the elbows, you lower the dumbbells to your sides and bring them back up in an arc motion.',
        videoUrl: 'https://www.youtube.com/embed/eozb-7_Dkdw',
        muscleGroups: ['Pectoralis Major', 'Deltoids'],
        sets: [{ id: 'lib-db-flys-s1', exerciseId: 'lib-db-flys', targetReps: '10-15' }, { id: 'lib-db-flys-s2', exerciseId: 'lib-db-flys', targetReps: '10-15' }, { id: 'lib-db-flys-s3', exerciseId: 'lib-db-flys', targetReps: '10-15' }],
      },
      {
        id: 'lib-incline-db-flys', name: 'Incline Dumbbell Flys', targetWeight: '10 lbs / 5 lbs', unit: 'reps',
        description: 'Performed on an incline bench, this fly variation focuses the isolation on the upper chest fibers.',
        videoUrl: 'https://www.youtube.com/embed/b26H_cX5x2s',
        muscleGroups: ['Upper Pectoralis', 'Anterior Deltoids'],
        sets: [{ id: 'lib-incline-db-flys-s1', exerciseId: 'lib-incline-db-flys', targetReps: '12-15' }, { id: 'lib-incline-db-flys-s2', exerciseId: 'lib-incline-db-flys', targetReps: '12-15' }, { id: 'lib-incline-db-flys-s3', exerciseId: 'lib-incline-db-flys', targetReps: '12-15' }],
      },
      {
        id: 'lib-cable-crossovers-high', name: 'Cable Crossovers (High to Low)', targetWeight: '20 lbs / 10 lbs per side', unit: 'reps',
        description: 'Standing between two high pulleys, you pull the handles downwards and across your body, targeting the lower chest.',
        videoUrl: 'https://www.youtube.com/embed/taI4aHQ_w4s',
        muscleGroups: ['Lower Pectoralis', 'Serratus Anterior'],
        sets: [{ id: 'lib-cable-crossovers-high-s1', exerciseId: 'lib-cable-crossovers-high', targetReps: '12-15' }, { id: 'lib-cable-crossovers-high-s2', exerciseId: 'lib-cable-crossovers-high', targetReps: '12-15' }, { id: 'lib-cable-crossovers-high-s3', exerciseId: 'lib-cable-crossovers-high', targetReps: '12-15' }],
      },
      {
        id: 'lib-cable-crossovers-low', name: 'Cable Crossovers (Low to High)', targetWeight: '15 lbs / 5 lbs per side', unit: 'reps',
        description: 'Standing between two low pulleys, you pull the handles upwards and across your body, targeting the upper chest.',
        videoUrl: 'https://www.youtube.com/embed/Iwe6AmxVf7o',
        muscleGroups: ['Upper Pectoralis', 'Serratus Anterior'],
        sets: [{ id: 'lib-cable-crossovers-low-s1', exerciseId: 'lib-cable-crossovers-low', targetReps: '12-15' }, { id: 'lib-cable-crossovers-low-s2', exerciseId: 'lib-cable-crossovers-low', targetReps: '12-15' }, { id: 'lib-cable-crossovers-low-s3', exerciseId: 'lib-cable-crossovers-low', targetReps: '12-15' }],
      },
      {
        id: 'lib-push-ups', name: 'Push-Ups', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'A classic bodyweight exercise performed by pushing your body up from the floor. Excellent for overall chest and triceps development.',
        videoUrl: 'https://www.youtube.com/embed/IODxDxX7oi4',
        muscleGroups: ['Pectoralis Major', 'Triceps', 'Deltoids'],
        sets: [{ id: 'lib-push-ups-s1', exerciseId: 'lib-push-ups', targetReps: 'To Failure' }, { id: 'lib-push-ups-s2', exerciseId: 'lib-push-ups', targetReps: 'To Failure' }, { id: 'lib-push-ups-s3', exerciseId: 'lib-push-ups', targetReps: 'To Failure' }],
      },
      {
        id: 'lib-chest-dips', name: 'Chest Dips', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'Performed on parallel bars, leaning your torso forward emphasizes the chest muscles, particularly the lower chest.',
        videoUrl: 'https://www.youtube.com/embed/c3ZGl4pAWiM',
        muscleGroups: ['Lower Pectoralis', 'Triceps', 'Deltoids'],
        sets: [{ id: 'lib-chest-dips-s1', exerciseId: 'lib-chest-dips', targetReps: 'To Failure' }, { id: 'lib-chest-dips-s2', exerciseId: 'lib-chest-dips', targetReps: 'To Failure' }, { id: 'lib-chest-dips-s3', exerciseId: 'lib-chest-dips', targetReps: 'To Failure' }],
      },
      {
        id: 'lib-machine-chest-press', name: 'Machine Chest Press', targetWeight: '60 lbs / 30 lbs', unit: 'reps',
        description: 'A seated machine exercise that mimics the bench press in a safer, more controlled manner. Great for beginners.',
        videoUrl: 'https://www.youtube.com/embed/Xa9-6pYk0_U',
        muscleGroups: ['Pectoralis Major', 'Triceps', 'Deltoids'],
        sets: [{ id: 'lib-machine-chest-press-s1', exerciseId: 'lib-machine-chest-press', targetReps: '10-15' }, { id: 'lib-machine-chest-press-s2', exerciseId: 'lib-machine-chest-press', targetReps: '10-15' }, { id: 'lib-machine-chest-press-s3', exerciseId: 'lib-machine-chest-press', targetReps: '10-15' }],
      },
      {
        id: 'lib-pec-deck-machine', name: 'Pec-Deck Machine', targetWeight: '50 lbs / 25 lbs', unit: 'reps',
        description: 'A seated machine fly that isolates the chest muscles. It provides constant tension throughout the entire movement.',
        videoUrl: 'https://www.youtube.com/embed/wPajg9-1x4o',
        muscleGroups: ['Pectoralis Major'],
        sets: [{ id: 'lib-pec-deck-machine-s1', exerciseId: 'lib-pec-deck-machine', targetReps: '12-15' }, { id: 'lib-pec-deck-machine-s2', exerciseId: 'lib-pec-deck-machine', targetReps: '12-15' }, { id: 'lib-pec-deck-machine-s3', exerciseId: 'lib-pec-deck-machine', targetReps: '12-15' }],
      },
      {
        id: 'lib-dumbbell-pullovers', name: 'Dumbbell Pullovers', targetWeight: '25 lbs / 10 lbs', unit: 'reps',
        description: 'Lying crossways on a bench, you lower a single dumbbell behind your head, stretching the lats and chest.',
        videoUrl: 'https://www.youtube.com/embed/Y_10hQ332_g',
        muscleGroups: ['Pectoralis Major', 'Latissimus Dorsi', 'Serratus Anterior'],
        sets: [{ id: 'lib-dumbbell-pullovers-s1', exerciseId: 'lib-dumbbell-pullovers', targetReps: '10-15' }, { id: 'lib-dumbbell-pullovers-s2', exerciseId: 'lib-dumbbell-pullovers', targetReps: '10-15' }, { id: 'lib-dumbbell-pullovers-s3', exerciseId: 'lib-dumbbell-pullovers', targetReps: '10-15' }],
      },
      {
        id: 'lib-dl', name: 'Deadlifts (Conventional)', targetWeight: '135 lbs / 75 lbs', unit: 'reps',
        description: 'A full-body compound exercise where you lift a loaded barbell from the floor to a standing position. The ultimate back and posterior chain builder.',
        videoUrl: 'https://www.youtube.com/embed/ytGaGIn3SjE',
        muscleGroups: ['Erector Spinae', 'Glutes', 'Hamstrings', 'Lats', 'Traps'],
        sets: [{ id: 'lib-dl-s1', exerciseId: 'lib-dl', targetReps: '3-6' }, { id: 'lib-dl-s2', exerciseId: 'lib-dl', targetReps: '3-6' }, { id: 'lib-dl-s3', exerciseId: 'lib-dl', targetReps: '3-6' }],
      },
      {
        id: 'lib-sumo-dl', name: 'Sumo Deadlifts', targetWeight: '135 lbs / 75 lbs', unit: 'reps',
        description: 'A deadlift variation with a wider stance and grip inside the legs, which engages the hips and quads more.',
        videoUrl: 'https://www.youtube.com/embed/Xsls8l4yI-c',
        muscleGroups: ['Glutes', 'Hamstrings', 'Quads', 'Erector Spinae', 'Traps'],
        sets: [{ id: 'lib-sumo-dl-s1', exerciseId: 'lib-sumo-dl', targetReps: '3-6' }, { id: 'lib-sumo-dl-s2', exerciseId: 'lib-sumo-dl', targetReps: '3-6' }, { id: 'lib-sumo-dl-s3', exerciseId: 'lib-sumo-dl', targetReps: '3-6' }],
      },
      {
        id: 'lib-pull-ups', name: 'Pull-Ups', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'A bodyweight exercise where you hang from a bar and pull yourself up until your chin is over it. Excellent for building back width.',
        videoUrl: 'https://www.youtube.com/embed/e_5z3A4D6Fk',
        muscleGroups: ['Latissimus Dorsi', 'Biceps', 'Rhomboids'],
        sets: [{ id: 'lib-pull-ups-s1', exerciseId: 'lib-pull-ups', targetReps: 'To Failure' }, { id: 'lib-pull-ups-s2', exerciseId: 'lib-pull-ups', targetReps: 'To Failure' }, { id: 'lib-pull-ups-s3', exerciseId: 'lib-pull-ups', targetReps: 'To Failure' }],
      },
      {
        id: 'lib-chin-ups', name: 'Chin-Ups', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'Similar to pull-ups but with an underhand (supinated) grip, which increases bicep involvement.',
        videoUrl: 'https://www.youtube.com/embed/b-2tM2n_p0M',
        muscleGroups: ['Latissimus Dorsi', 'Biceps', 'Rhomboids'],
        sets: [{ id: 'lib-chin-ups-s1', exerciseId: 'lib-chin-ups', targetReps: 'To Failure' }, { id: 'lib-chin-ups-s2', exerciseId: 'lib-chin-ups', targetReps: 'To Failure' }, { id: 'lib-chin-ups-s3', exerciseId: 'lib-chin-ups', targetReps: 'To Failure' }],
      },
      {
        id: 'lib-bent-over-rows', name: 'Bent-Over Barbell Rows', targetWeight: '85 lbs / 45 lbs', unit: 'reps',
        description: 'A compound exercise where you hinge at the hips and pull a barbell towards your lower chest, building back thickness.',
        videoUrl: 'https://www.youtube.com/embed/vT2GjY_Umpw',
        muscleGroups: ['Latissimus Dorsi', 'Rhomboids', 'Traps', 'Biceps'],
        sets: [{ id: 'lib-bent-over-rows-s1', exerciseId: 'lib-bent-over-rows', targetReps: '6-10' }, { id: 'lib-bent-over-rows-s2', exerciseId: 'lib-bent-over-rows', targetReps: '6-10' }, { id: 'lib-bent-over-rows-s3', exerciseId: 'lib-bent-over-rows', targetReps: '6-10' }, { id: 'lib-bent-over-rows-s4', exerciseId: 'lib-bent-over-rows', targetReps: '6-10' }],
      },
      {
        id: 'lib-pendlay-rows', name: 'Pendlay Rows', targetWeight: '95 lbs / 55 lbs', unit: 'reps',
        description: 'A stricter version of the barbell row where the barbell rests on the floor between each rep, building explosive power.',
        videoUrl: 'https://www.youtube.com/embed/h_QF_2-soGg',
        muscleGroups: ['Latissimus Dorsi', 'Rhomboids', 'Traps', 'Erector Spinae'],
        sets: [{ id: 'lib-pendlay-rows-s1', exerciseId: 'lib-pendlay-rows', targetReps: '5-8' }, { id: 'lib-pendlay-rows-s2', exerciseId: 'lib-pendlay-rows', targetReps: '5-8' }, { id: 'lib-pendlay-rows-s3', exerciseId: 'lib-pendlay-rows', targetReps: '5-8' }],
      },
      {
        id: 'lib-db-rows', name: 'Dumbbell Rows', targetWeight: '25 lbs / 15 lbs', unit: 'reps',
        description: 'A unilateral rowing exercise, typically performed with one knee and hand on a bench, which helps isolate the lats.',
        videoUrl: 'https://www.youtube.com/embed/pYcpY20QaE8',
        muscleGroups: ['Latissimus Dorsi', 'Rhomboids', 'Biceps'],
        sets: [{ id: 'lib-db-rows-s1', exerciseId: 'lib-db-rows', targetReps: '8-12 per side' }, { id: 'lib-db-rows-s2', exerciseId: 'lib-db-rows', targetReps: '8-12 per side' }, { id: 'lib-db-rows-s3', exerciseId: 'lib-db-rows', targetReps: '8-12 per side' }],
      },
      {
        id: 'lib-t-bar-rows', name: 'T-Bar Rows', targetWeight: '45 lbs / 25 lbs plate', unit: 'reps',
        description: 'A rowing variation using a T-bar machine or a barbell wedged into a corner. Allows for heavy weight and targets the mid-back.',
        videoUrl: 'https://www.youtube.com/embed/j3Igk5nyZE4',
        muscleGroups: ['Rhomboids', 'Latissimus Dorsi', 'Traps'],
        sets: [{ id: 'lib-t-bar-rows-s1', exerciseId: 'lib-t-bar-rows', targetReps: '8-12' }, { id: 'lib-t-bar-rows-s2', exerciseId: 'lib-t-bar-rows', targetReps: '8-12' }, { id: 'lib-t-bar-rows-s3', exerciseId: 'lib-t-bar-rows', targetReps: '8-12' }],
      },
      {
        id: 'lib-cable-rows', name: 'Seated Cable Rows', targetWeight: '50 lbs / 30 lbs', unit: 'reps',
        description: 'A machine-based rowing exercise that targets the mid-back and is excellent for improving posture.',
        videoUrl: 'https://www.youtube.com/embed/GZbfZ033f74',
        muscleGroups: ['Rhomboids', 'Latissimus Dorsi', 'Biceps'],
        sets: [{ id: 'lib-cable-rows-s1', exerciseId: 'lib-cable-rows', targetReps: '10-15' }, { id: 'lib-cable-rows-s2', exerciseId: 'lib-cable-rows', targetReps: '10-15' }, { id: 'lib-cable-rows-s3', exerciseId: 'lib-cable-rows', targetReps: '10-15' }],
      },
      {
        id: 'lib-lat-pulldowns', name: 'Lat Pulldowns', targetWeight: '70 lbs / 40 lbs', unit: 'reps',
        description: 'A machine exercise that simulates a pull-up. Great for targeting the lats and building back width.',
        videoUrl: 'https://www.youtube.com/embed/0oe_dj_G9oU',
        muscleGroups: ['Latissimus Dorsi', 'Biceps'],
        sets: [{ id: 'lib-lat-pulldowns-s1', exerciseId: 'lib-lat-pulldowns', targetReps: '10-12' }, { id: 'lib-lat-pulldowns-s2', exerciseId: 'lib-lat-pulldowns', targetReps: '10-12' }, { id: 'lib-lat-pulldowns-s3', exerciseId: 'lib-lat-pulldowns', targetReps: '10-12' }],
      },
      {
        id: 'lib-straight-arm-pulldowns', name: 'Straight-Arm Pulldowns', targetWeight: '30 lbs / 15 lbs', unit: 'reps',
        description: 'An isolation exercise using a cable machine that targets the lats while minimizing bicep involvement.',
        videoUrl: 'https://www.youtube.com/embed/r34PR1mx6g8',
        muscleGroups: ['Latissimus Dorsi', 'Serratus Anterior'],
        sets: [{ id: 'lib-straight-arm-pulldowns-s1', exerciseId: 'lib-straight-arm-pulldowns', targetReps: '12-15' }, { id: 'lib-straight-arm-pulldowns-s2', exerciseId: 'lib-straight-arm-pulldowns', targetReps: '12-15' }, { id: 'lib-straight-arm-pulldowns-s3', exerciseId: 'lib-straight-arm-pulldowns', targetReps: '12-15' }],
      },
      {
        id: 'lib-good-mornings', name: 'Good Mornings', targetWeight: 'Bar only / 35 lbs', unit: 'reps',
        description: 'A hip-hinge exercise that targets the hamstrings and lower back. Performed by placing a barbell on the shoulders and bending forward.',
        videoUrl: 'https://www.youtube.com/embed/vKPGe8zb2S4',
        muscleGroups: ['Erector Spinae', 'Glutes', 'Hamstrings'],
        sets: [{ id: 'lib-good-mornings-s1', exerciseId: 'lib-good-mornings', targetReps: '8-12' }, { id: 'lib-good-mornings-s2', exerciseId: 'lib-good-mornings', targetReps: '8-12' }, { id: 'lib-good-mornings-s3', exerciseId: 'lib-good-mornings', targetReps: '8-12' }],
      },
      {
        id: 'lib-back-extensions', name: 'Back Extensions (Hyperextensions)', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'An exercise performed on a hyperextension bench to strengthen the lower back, glutes, and hamstrings.',
        videoUrl: 'https://www.youtube.com/embed/ph3pddR_PBo',
        muscleGroups: ['Erector Spinae', 'Glutes', 'Hamstrings'],
        sets: [{ id: 'lib-back-extensions-s1', exerciseId: 'lib-back-extensions', targetReps: '12-15' }, { id: 'lib-back-extensions-s2', exerciseId: 'lib-back-extensions', targetReps: '12-15' }, { id: 'lib-back-extensions-s3', exerciseId: 'lib-back-extensions', targetReps: '12-15' }],
      },
      {
        id: 'lib-rack-pulls', name: 'Rack Pulls', targetWeight: '185 lbs / 95 lbs', unit: 'reps',
        description: 'A deadlift variation performed from an elevated position (in a power rack), allowing you to use heavier weight to target the upper back and traps.',
        videoUrl: 'https://www.youtube.com/embed/Xh_g_9U5_3U',
        muscleGroups: ['Trapezius', 'Rhomboids', 'Lats', 'Erector Spinae'],
        sets: [{ id: 'lib-rack-pulls-s1', exerciseId: 'lib-rack-pulls', targetReps: '3-6' }, { id: 'lib-rack-pulls-s2', exerciseId: 'lib-rack-pulls', targetReps: '3-6' }, { id: 'lib-rack-pulls-s3', exerciseId: 'lib-rack-pulls', targetReps: '3-6' }],
      },
      {
        id: 'lib-inverted-rows', name: 'Inverted Rows', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'A bodyweight rowing exercise where you lie under a fixed bar and pull your chest up to it. A great precursor to pull-ups.',
        videoUrl: 'https://www.youtube.com/embed/hXTc1mDn2yY',
        muscleGroups: ['Rhomboids', 'Lats', 'Biceps', 'Posterior Deltoids'],
        sets: [{ id: 'lib-inverted-rows-s1', exerciseId: 'lib-inverted-rows', targetReps: 'To Failure' }, { id: 'lib-inverted-rows-s2', exerciseId: 'lib-inverted-rows', targetReps: 'To Failure' }, { id: 'lib-inverted-rows-s3', exerciseId: 'lib-inverted-rows', targetReps: 'To Failure' }],
      },
      {
        id: 'lib-back-squats', name: 'Barbell Back Squats', targetWeight: '95 lbs / 45 lbs', unit: 'reps',
        description: 'A foundational lower body exercise where you squat down with a barbell resting on your upper back. The "king" of leg exercises.',
        videoUrl: 'https://www.youtube.com/embed/bEv6CCg2BC8',
        muscleGroups: ['Quadriceps', 'Glutes', 'Hamstrings', 'Calves', 'Core'],
        sets: [{ id: 'lib-back-squats-s1', exerciseId: 'lib-back-squats', targetReps: '5-8' }, { id: 'lib-back-squats-s2', exerciseId: 'lib-back-squats', targetReps: '5-8' }, { id: 'lib-back-squats-s3', exerciseId: 'lib-back-squats', targetReps: '5-8' }],
      },
      {
        id: 'lib-front-squats', name: 'Front Squats', targetWeight: '75 lbs / 35 lbs', unit: 'reps',
        description: 'A squat variation where the barbell is held in front of the body on the shoulders, which emphasizes the quads and requires more core stability.',
        videoUrl: 'https://www.youtube.com/embed/uYewPz_YSbA',
        muscleGroups: ['Quadriceps', 'Glutes', 'Core'],
        sets: [{ id: 'lib-front-squats-s1', exerciseId: 'lib-front-squats', targetReps: '6-10' }, { id: 'lib-front-squats-s2', exerciseId: 'lib-front-squats', targetReps: '6-10' }, { id: 'lib-front-squats-s3', exerciseId: 'lib-front-squats', targetReps: '6-10' }],
      },
      {
        id: 'lib-goblet-squats', name: 'Goblet Squats', targetWeight: '25 lbs / 15 lbs', unit: 'reps',
        description: 'A squat performed while holding a single dumbbell or kettlebell at chest level. Excellent for teaching proper squat form.',
        videoUrl: 'https://www.youtube.com/embed/MeW1_r32I3o',
        muscleGroups: ['Quadriceps', 'Glutes', 'Core'],
        sets: [{ id: 'lib-goblet-squats-s1', exerciseId: 'lib-goblet-squats', targetReps: '10-15' }, { id: 'lib-goblet-squats-s2', exerciseId: 'lib-goblet-squats', targetReps: '10-15' }, { id: 'lib-goblet-squats-s3', exerciseId: 'lib-goblet-squats', targetReps: '10-15' }],
      },
      {
        id: 'lib-leg-press', name: 'Leg Press', targetWeight: '180 lbs / 90 lbs', unit: 'reps',
        description: 'A machine-based exercise where you press a weighted platform away with your feet. Great for building leg mass with less strain on the back.',
        videoUrl: 'https://www.youtube.com/embed/s8-89_iT_aQ',
        muscleGroups: ['Quadriceps', 'Glutes', 'Hamstrings'],
        sets: [{ id: 'lib-leg-press-s1', exerciseId: 'lib-leg-press', targetReps: '10-15' }, { id: 'lib-leg-press-s2', exerciseId: 'lib-leg-press', targetReps: '10-15' }, { id: 'lib-leg-press-s3', exerciseId: 'lib-leg-press', targetReps: '10-15' }],
      },
      {
        id: 'lib-rdls', name: 'Romanian Deadlifts (RDLs)', targetWeight: '95 lbs / 55 lbs', unit: 'reps',
        description: 'A deadlift variation focusing on the hip hinge with minimal knee bend to primarily target the hamstrings and glutes.',
        videoUrl: 'https://www.youtube.com/embed/2z8JmcrW-As',
        muscleGroups: ['Hamstrings', 'Glutes', 'Erector Spinae'],
        sets: [{ id: 'lib-rdls-s1', exerciseId: 'lib-rdls', targetReps: '8-12' }, { id: 'lib-rdls-s2', exerciseId: 'lib-rdls', targetReps: '8-12' }, { id: 'lib-rdls-s3', exerciseId: 'lib-rdls', targetReps: '8-12' }],
      },
      {
        id: 'lib-walking-lunges', name: 'Walking Lunges', targetWeight: '15 lbs / 5 lbs dumbbells', unit: 'reps',
        description: 'A dynamic lunge variation where you step forward into a lunge with alternating legs. Improves balance and targets each leg individually.',
        videoUrl: 'https://www.youtube.com/embed/QO_o3_5_1_U',
        muscleGroups: ['Quadriceps', 'Glutes', 'Hamstrings'],
        sets: [{ id: 'lib-walking-lunges-s1', exerciseId: 'lib-walking-lunges', targetReps: '10-12 per leg' }, { id: 'lib-walking-lunges-s2', exerciseId: 'lib-walking-lunges', targetReps: '10-12 per leg' }, { id: 'lib-walking-lunges-s3', exerciseId: 'lib-walking-lunges', targetReps: '10-12 per leg' }],
      },
      {
        id: 'lib-bulgarian-split-squats', name: 'Bulgarian Split Squats', targetWeight: '10 lbs / 5 lbs dumbbells', unit: 'reps',
        description: 'A single-leg squat variation with the rear foot elevated on a bench, which intensely targets the quads and glutes of the front leg.',
        videoUrl: 'https://www.youtube.com/embed/2C-uNgKwPLE',
        muscleGroups: ['Quadriceps', 'Glutes', 'Hamstrings'],
        sets: [{ id: 'lib-bulgarian-split-squats-s1', exerciseId: 'lib-bulgarian-split-squats', targetReps: '8-12 per leg' }, { id: 'lib-bulgarian-split-squats-s2', exerciseId: 'lib-bulgarian-split-squats', targetReps: '8-12 per leg' }, { id: 'lib-bulgarian-split-squats-s3', exerciseId: 'lib-bulgarian-split-squats', targetReps: '8-12 per leg' }],
      },
      {
        id: 'lib-leg-extensions', name: 'Leg Extensions', targetWeight: '40 lbs / 20 lbs', unit: 'reps',
        description: 'An isolation machine exercise that specifically targets the quadriceps muscles.',
        videoUrl: 'https://www.youtube.com/embed/YyvSfVjQeL0',
        muscleGroups: ['Quadriceps'],
        sets: [{ id: 'lib-leg-extensions-s1', exerciseId: 'lib-leg-extensions', targetReps: '12-15' }, { id: 'lib-leg-extensions-s2', exerciseId: 'lib-leg-extensions', targetReps: '12-15' }, { id: 'lib-leg-extensions-s3', exerciseId: 'lib-leg-extensions', targetReps: '12-15' }],
      },
      {
        id: 'lib-leg-curls', name: 'Leg Curls (Lying or Seated)', targetWeight: '40 lbs / 20 lbs', unit: 'reps',
        description: 'An isolation machine exercise that targets the hamstrings. Can be performed either lying face down or seated.',
        videoUrl: 'https://www.youtube.com/embed/1Tq3QdYUuHs',
        muscleGroups: ['Hamstrings'],
        sets: [{ id: 'lib-leg-curls-s1', exerciseId: 'lib-leg-curls', targetReps: '12-15' }, { id: 'lib-leg-curls-s2', exerciseId: 'lib-leg-curls', targetReps: '12-15' }, { id: 'lib-leg-curls-s3', exerciseId: 'lib-leg-curls', targetReps: '12-15' }],
      },
      {
        id: 'lib-standing-calf-raises', name: 'Standing Calf Raises', targetWeight: '45 lbs / 25 lbs', unit: 'reps',
        description: 'An isolation exercise for the larger gastrocnemius muscle of the calf. Can be done on a machine or with free weights.',
        videoUrl: 'https://www.youtube.com/embed/Jfl_g_h_AnA',
        muscleGroups: ['Gastrocnemius', 'Soleus'],
        sets: [{ id: 'lib-standing-calf-raises-s1', exerciseId: 'lib-standing-calf-raises', targetReps: '15-25' }, { id: 'lib-standing-calf-raises-s2', exerciseId: 'lib-standing-calf-raises', targetReps: '15-25' }, { id: 'lib-standing-calf-raises-s3', exerciseId: 'lib-standing-calf-raises', targetReps: '15-25' }, { id: 'lib-standing-calf-raises-s4', exerciseId: 'lib-standing-calf-raises', targetReps: '15-25' }],
      },
      {
        id: 'lib-seated-calf-raises', name: 'Seated Calf Raises', targetWeight: '45 lbs / 25 lbs', unit: 'reps',
        description: 'An isolation exercise that primarily targets the soleus muscle of the calf due to the knee being bent.',
        videoUrl: 'https://www.youtube.com/embed/nDFgC_ghrB8',
        muscleGroups: ['Soleus'],
        sets: [{ id: 'lib-seated-calf-raises-s1', exerciseId: 'lib-seated-calf-raises', targetReps: '15-25' }, { id: 'lib-seated-calf-raises-s2', exerciseId: 'lib-seated-calf-raises', targetReps: '15-25' }, { id: 'lib-seated-calf-raises-s3', exerciseId: 'lib-seated-calf-raises', targetReps: '15-25' }, { id: 'lib-seated-calf-raises-s4', exerciseId: 'lib-seated-calf-raises', targetReps: '15-25' }],
      },
      {
        id: 'lib-hip-thrusts', name: 'Hip Thrusts', targetWeight: '95 lbs / 45 lbs', unit: 'reps',
        description: 'Performed with your upper back on a bench and a barbell across your hips, this is one of the best exercises for glute development.',
        videoUrl: 'https://www.youtube.com/embed/xDmFkJxPzeM',
        muscleGroups: ['Glutes', 'Hamstrings'],
        sets: [{ id: 'lib-hip-thrusts-s1', exerciseId: 'lib-hip-thrusts', targetReps: '8-12' }, { id: 'lib-hip-thrusts-s2', exerciseId: 'lib-hip-thrusts', targetReps: '8-12' }, { id: 'lib-hip-thrusts-s3', exerciseId: 'lib-hip-thrusts', targetReps: '8-12' }, { id: 'lib-hip-thrusts-s4', exerciseId: 'lib-hip-thrusts', targetReps: '8-12' }],
      },
      {
        id: 'lib-hack-squats', name: 'Hack Squats', targetWeight: '90 lbs / 45 lbs', unit: 'reps',
        description: 'A machine-based squat that provides support for the back, allowing for a deep range of motion to target the quads.',
        videoUrl: 'https://www.youtube.com/embed/0tn5_9DBA7g',
        muscleGroups: ['Quadriceps', 'Glutes'],
        sets: [{ id: 'lib-hack-squats-s1', exerciseId: 'lib-hack-squats', targetReps: '10-15' }, { id: 'lib-hack-squats-s2', exerciseId: 'lib-hack-squats', targetReps: '10-15' }, { id: 'lib-hack-squats-s3', exerciseId: 'lib-hack-squats', targetReps: '10-15' }],
      },
      {
        id: 'lib-box-jumps', name: 'Box Jumps', targetWeight: 'Bodyweight (box height varies)', unit: 'reps',
        description: 'A plyometric exercise where you jump from the floor onto an elevated box, developing explosive power in the lower body.',
        videoUrl: 'https://www.youtube.com/embed/52r3wxtaA7o',
        muscleGroups: ['Glutes', 'Quads', 'Hamstrings', 'Calves'],
        sets: [{ id: 'lib-box-jumps-s1', exerciseId: 'lib-box-jumps', targetReps: '5-8' }, { id: 'lib-box-jumps-s2', exerciseId: 'lib-box-jumps', targetReps: '5-8' }, { id: 'lib-box-jumps-s3', exerciseId: 'lib-box-jumps', targetReps: '5-8' }],
      },
      {
        id: 'lib-sissy-squats', name: 'Sissy Squats', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'An advanced bodyweight squat variation that isolates the quadriceps by leaning back and rising on the balls of your feet.',
        videoUrl: 'https://www.youtube.com/embed/gdi-aQ013pM',
        muscleGroups: ['Quadriceps'],
        sets: [{ id: 'lib-sissy-squats-s1', exerciseId: 'lib-sissy-squats', targetReps: 'To Failure' }, { id: 'lib-sissy-squats-s2', exerciseId: 'lib-sissy-squats', targetReps: 'To Failure' }, { id: 'lib-sissy-squats-s3', exerciseId: 'lib-sissy-squats', targetReps: 'To Failure' }],
      },
      {
        id: 'lib-ohp', name: 'Overhead Press (Barbell)', targetWeight: '65 lbs / 35 lbs', unit: 'reps',
        description: 'A compound lift, also known as the military press, where you press a barbell overhead from a standing or seated position.',
        videoUrl: 'https://www.youtube.com/embed/2yjwXTZQDDI',
        muscleGroups: ['Deltoids', 'Triceps', 'Traps'],
        sets: [{ id: 'lib-ohp-s1', exerciseId: 'lib-ohp', targetReps: '6-10' }, { id: 'lib-ohp-s2', exerciseId: 'lib-ohp', targetReps: '6-10' }, { id: 'lib-ohp-s3', exerciseId: 'lib-ohp', targetReps: '6-10' }],
      },
      {
        id: 'lib-seated-db-press', name: 'Seated Dumbbell Press', targetWeight: '20 lbs / 10 lbs', unit: 'reps',
        description: 'A shoulder press variation using dumbbells while seated, which provides back support and allows for a neutral grip.',
        videoUrl: 'https://www.youtube.com/embed/qEwKCR5JCog',
        muscleGroups: ['Deltoids', 'Triceps'],
        sets: [{ id: 'lib-seated-db-press-s1', exerciseId: 'lib-seated-db-press', targetReps: '8-12' }, { id: 'lib-seated-db-press-s2', exerciseId: 'lib-seated-db-press', targetReps: '8-12' }, { id: 'lib-seated-db-press-s3', exerciseId: 'lib-seated-db-press', targetReps: '8-12' }],
      },
      {
        id: 'lib-arnold-press', name: 'Arnold Press', targetWeight: '15 lbs / 5 lbs', unit: 'reps',
        description: 'A dumbbell press variation named after Arnold Schwarzenegger. It involves rotating the palms from facing you to facing forward, hitting all three deltoid heads.',
        videoUrl: 'https://www.youtube.com/embed/6Z1_GfbY-c0',
        muscleGroups: ['All three Deltoid heads', 'Triceps'],
        sets: [{ id: 'lib-arnold-press-s1', exerciseId: 'lib-arnold-press', targetReps: '8-12' }, { id: 'lib-arnold-press-s2', exerciseId: 'lib-arnold-press', targetReps: '8-12' }, { id: 'lib-arnold-press-s3', exerciseId: 'lib-arnold-press', targetReps: '8-12' }],
      },
      {
        id: 'lib-lateral-raises', name: 'Lateral Raises', targetWeight: '10 lbs / 5 lbs', unit: 'reps',
        description: 'An isolation exercise for the lateral (side) deltoids. You raise dumbbells out to your sides until they are at shoulder height.',
        videoUrl: 'https://www.youtube.com/embed/3VcKaXpzqRo',
        muscleGroups: ['Lateral Deltoids'],
        sets: [{ id: 'lib-lateral-raises-s1', exerciseId: 'lib-lateral-raises', targetReps: '12-15' }, { id: 'lib-lateral-raises-s2', exerciseId: 'lib-lateral-raises', targetReps: '12-15' }, { id: 'lib-lateral-raises-s3', exerciseId: 'lib-lateral-raises', targetReps: '12-15' }],
      },
      {
        id: 'lib-bent-over-db-raises', name: 'Bent-Over Dumbbell Raises', targetWeight: '10 lbs / 5 lbs', unit: 'reps',
        description: 'An isolation exercise targeting the posterior (rear) deltoids by hinging at the hips and raising dumbbells out to the sides.',
        videoUrl: 'https://www.youtube.com/embed/3dgy9JUAz1g',
        muscleGroups: ['Posterior Deltoids', 'Rhomboids'],
        sets: [{ id: 'lib-bent-over-db-raises-s1', exerciseId: 'lib-bent-over-db-raises', targetReps: '12-15' }, { id: 'lib-bent-over-db-raises-s2', exerciseId: 'lib-bent-over-db-raises', targetReps: '12-15' }, { id: 'lib-bent-over-db-raises-s3', exerciseId: 'lib-bent-over-db-raises', targetReps: '12-15' }],
      },
      {
        id: 'lib-front-raises', name: 'Front Raises', targetWeight: '10 lbs / 5 lbs', unit: 'reps',
        description: 'An isolation exercise for the anterior (front) deltoids, performed by raising dumbbells, a plate, or a barbell in front of you.',
        videoUrl: 'https://www.youtube.com/embed/s_L0Jd_Al_M',
        muscleGroups: ['Anterior Deltoids'],
        sets: [{ id: 'lib-front-raises-s1', exerciseId: 'lib-front-raises', targetReps: '10-15' }, { id: 'lib-front-raises-s2', exerciseId: 'lib-front-raises', targetReps: '10-15' }, { id: 'lib-front-raises-s3', exerciseId: 'lib-front-raises', targetReps: '10-15' }],
      },
      {
        id: 'lib-upright-rows', name: 'Upright Rows', targetWeight: '45 lbs / 25 lbs', unit: 'reps',
        description: 'A compound exercise that targets the traps and deltoids by pulling a barbell or dumbbells straight up towards the chin.',
        videoUrl: 'https://www.youtube.com/embed/Y_QzC_Etrb4',
        muscleGroups: ['Trapezius', 'Deltoids', 'Biceps'],
        sets: [{ id: 'lib-upright-rows-s1', exerciseId: 'lib-upright-rows', targetReps: '10-12' }, { id: 'lib-upright-rows-s2', exerciseId: 'lib-upright-rows', targetReps: '10-12' }, { id: 'lib-upright-rows-s3', exerciseId: 'lib-upright-rows', targetReps: '10-12' }],
      },
      {
        id: 'lib-face-pulls', name: 'Face Pulls', targetWeight: '20 lbs / 10 lbs', unit: 'reps',
        description: 'A crucial exercise for shoulder health, targeting the rear deltoids and upper back muscles using a rope attachment on a cable machine.',
        videoUrl: 'https://www.youtube.com/embed/eIq5CB9wyoE',
        muscleGroups: ['Posterior Deltoids', 'Rhomboids', 'Traps'],
        sets: [{ id: 'lib-face-pulls-s1', exerciseId: 'lib-face-pulls', targetReps: '15-20' }, { id: 'lib-face-pulls-s2', exerciseId: 'lib-face-pulls', targetReps: '15-20' }, { id: 'lib-face-pulls-s3', exerciseId: 'lib-face-pulls', targetReps: '15-20' }],
      },
      {
        id: 'lib-barbell-shrugs', name: 'Barbell Shrugs', targetWeight: '135 lbs / 75 lbs', unit: 'reps',
        description: 'An isolation exercise for the upper trapezius muscles. You hold a heavy barbell and shrug your shoulders upwards.',
        videoUrl: 'https://www.youtube.com/embed/gOM-332eA4U',
        muscleGroups: ['Upper Trapezius'],
        sets: [{ id: 'lib-barbell-shrugs-s1', exerciseId: 'lib-barbell-shrugs', targetReps: '8-12' }, { id: 'lib-barbell-shrugs-s2', exerciseId: 'lib-barbell-shrugs', targetReps: '8-12' }, { id: 'lib-barbell-shrugs-s3', exerciseId: 'lib-barbell-shrugs', targetReps: '8-12' }],
      },
      {
        id: 'lib-dumbbell-shrugs', name: 'Dumbbell Shrugs', targetWeight: '40 lbs / 20 lbs', unit: 'reps',
        description: 'Similar to the barbell version but with dumbbells, allowing for a more natural range of motion.',
        videoUrl: 'https://www.youtube.com/embed/8lP_eJOFbV8',
        muscleGroups: ['Upper Trapezius'],
        sets: [{ id: 'lib-dumbbell-shrugs-s1', exerciseId: 'lib-dumbbell-shrugs', targetReps: '10-15' }, { id: 'lib-dumbbell-shrugs-s2', exerciseId: 'lib-dumbbell-shrugs', targetReps: '10-15' }, { id: 'lib-dumbbell-shrugs-s3', exerciseId: 'lib-dumbbell-shrugs', targetReps: '10-15' }],
      },
      {
        id: 'lib-landmine-press', name: 'Landmine Press', targetWeight: '25 lbs / 10 lbs plate', unit: 'reps',
        description: 'A shoulder-friendly pressing variation where you press one end of a barbell upwards from a kneeling or standing position.',
        videoUrl: 'https://www.youtube.com/embed/R2I1_o_pS3A',
        muscleGroups: ['Anterior Deltoids', 'Upper Pectoralis', 'Triceps'],
        sets: [{ id: 'lib-landmine-press-s1', exerciseId: 'lib-landmine-press', targetReps: '8-12 per side' }, { id: 'lib-landmine-press-s2', exerciseId: 'lib-landmine-press', targetReps: '8-12 per side' }, { id: 'lib-landmine-press-s3', exerciseId: 'lib-landmine-press', targetReps: '8-12 per side' }],
      },
      {
        id: 'lib-pike-push-ups', name: 'Pike Push-Ups', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'A challenging bodyweight exercise that simulates an overhead press, targeting the shoulders and triceps.',
        videoUrl: 'https://www.youtube.com/embed/mYdOknQ_24M',
        muscleGroups: ['Deltoids', 'Triceps'],
        sets: [{ id: 'lib-pike-push-ups-s1', exerciseId: 'lib-pike-push-ups', targetReps: 'To Failure' }, { id: 'lib-pike-push-ups-s2', exerciseId: 'lib-pike-push-ups', targetReps: 'To Failure' }, { id: 'lib-pike-push-ups-s3', exerciseId: 'lib-pike-push-ups', targetReps: 'To Failure' }],
      },
      {
        id: 'lib-cable-lateral-raises', name: 'Cable Lateral Raises', targetWeight: '10 lbs / 5 lbs', unit: 'reps',
        description: 'A lateral raise variation using a low cable pulley, which provides constant tension on the deltoid throughout the movement.',
        videoUrl: 'https://www.youtube.com/embed/p4l5gtoaH0M',
        muscleGroups: ['Lateral Deltoids'],
        sets: [{ id: 'lib-cable-lateral-raises-s1', exerciseId: 'lib-cable-lateral-raises', targetReps: '12-15 per side' }, { id: 'lib-cable-lateral-raises-s2', exerciseId: 'lib-cable-lateral-raises', targetReps: '12-15 per side' }, { id: 'lib-cable-lateral-raises-s3', exerciseId: 'lib-cable-lateral-raises', targetReps: '12-15 per side' }],
      },
      {
        id: 'lib-reverse-pec-deck', name: 'Reverse Pec-Deck', targetWeight: '40 lbs / 20 lbs', unit: 'reps',
        description: 'A machine exercise that isolates the posterior deltoids and upper back muscles.',
        videoUrl: 'https://www.youtube.com/embed/5_HJm609L7g',
        muscleGroups: ['Posterior Deltoids', 'Rhomboids'],
        sets: [{ id: 'lib-reverse-pec-deck-s1', exerciseId: 'lib-reverse-pec-deck', targetReps: '12-15' }, { id: 'lib-reverse-pec-deck-s2', exerciseId: 'lib-reverse-pec-deck', targetReps: '12-15' }, { id: 'lib-reverse-pec-deck-s3', exerciseId: 'lib-reverse-pec-deck', targetReps: '12-15' }],
      },
      {
        id: 'lib-handstand-push-ups', name: 'Handstand Push-Ups', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'An advanced calisthenics exercise that involves doing a push-up while in a handstand position against a wall. The ultimate bodyweight shoulder exercise.',
        videoUrl: 'https://www.youtube.com/embed/d_M-v-g_FFI',
        muscleGroups: ['Deltoids', 'Triceps', 'Traps'],
        sets: [{ id: 'lib-handstand-push-ups-s1', exerciseId: 'lib-handstand-push-ups', targetReps: 'To Failure' }, { id: 'lib-handstand-push-ups-s2', exerciseId: 'lib-handstand-push-ups', targetReps: 'To Failure' }, { id: 'lib-handstand-push-ups-s3', exerciseId: 'lib-handstand-push-ups', targetReps: 'To Failure' }],
      },
      {
        id: 'lib-barbell-curls', name: 'Barbell Curls', targetWeight: '45 lbs / 25 lbs', unit: 'reps',
        description: 'The classic mass builder for biceps. Stand and curl a barbell up towards your shoulders, keeping your elbows stationary.',
        videoUrl: 'https://www.youtube.com/embed/kwG2ipFRgfo',
        muscleGroups: ['Biceps Brachii'],
        sets: [{ id: 'lib-barbell-curls-s1', exerciseId: 'lib-barbell-curls', targetReps: '8-12' }, { id: 'lib-barbell-curls-s2', exerciseId: 'lib-barbell-curls', targetReps: '8-12' }, { id: 'lib-barbell-curls-s3', exerciseId: 'lib-barbell-curls', targetReps: '8-12' }],
      },
      {
        id: 'lib-db-bicep-curls', name: 'Dumbbell Bicep Curls', targetWeight: '20 lbs / 10 lbs', unit: 'reps',
        description: 'The dumbbell version of the bicep curl, allowing for supination (twisting the wrist) to fully engage the bicep peak.',
        videoUrl: 'https://www.youtube.com/embed/yTWO2th-RIY',
        muscleGroups: ['Biceps Brachii'],
        sets: [{ id: 'lib-db-bicep-curls-s1', exerciseId: 'lib-db-bicep-curls', targetReps: '10-12 per side' }, { id: 'lib-db-bicep-curls-s2', exerciseId: 'lib-db-bicep-curls', targetReps: '10-12 per side' }, { id: 'lib-db-bicep-curls-s3', exerciseId: 'lib-db-bicep-curls', targetReps: '10-12 per side' }],
      },
      {
        id: 'lib-hammer-curls', name: 'Hammer Curls', targetWeight: '15 lbs / 5 lbs', unit: 'reps',
        description: 'A bicep curl with a neutral (hammer) grip. This targets the brachialis and brachioradialis in addition to the biceps, building arm thickness.',
        videoUrl: 'https://www.youtube.com/embed/zC3nLHv29AI',
        muscleGroups: ['Biceps', 'Brachialis', 'Brachioradialis'],
        sets: [{ id: 'lib-hammer-curls-s1', exerciseId: 'lib-hammer-curls', targetReps: '10-15' }, { id: 'lib-hammer-curls-s2', exerciseId: 'lib-hammer-curls', targetReps: '10-15' }, { id: 'lib-hammer-curls-s3', exerciseId: 'lib-hammer-curls', targetReps: '10-15' }],
      },
      {
        id: 'lib-preacher-curls', name: 'Preacher Curls', targetWeight: '35 lbs / 15 lbs', unit: 'reps',
        description: 'An isolation curl performed on a preacher bench, which prevents cheating and maximizes bicep contraction.',
        videoUrl: 'https://www.youtube.com/embed/fIWP-FRFNU0',
        muscleGroups: ['Biceps Brachii'],
        sets: [{ id: 'lib-preacher-curls-s1', exerciseId: 'lib-preacher-curls', targetReps: '10-12' }, { id: 'lib-preacher-curls-s2', exerciseId: 'lib-preacher-curls', targetReps: '10-12' }, { id: 'lib-preacher-curls-s3', exerciseId: 'lib-preacher-curls', targetReps: '10-12' }],
      },
      {
        id: 'lib-concentration-curls', name: 'Concentration Curls', targetWeight: '15 lbs / 5 lbs', unit: 'reps',
        description: 'A seated curl where the elbow is braced against the inner thigh, providing strict isolation of the bicep.',
        videoUrl: 'https://www.youtube.com/embed/0AUGkch3tzc',
        muscleGroups: ['Biceps Brachii'],
        sets: [{ id: 'lib-concentration-curls-s1', exerciseId: 'lib-concentration-curls', targetReps: '10-15 per side' }, { id: 'lib-concentration-curls-s2', exerciseId: 'lib-concentration-curls', targetReps: '10-15 per side' }],
      },
      {
        id: 'lib-cable-curls', name: 'Cable Curls', targetWeight: '30 lbs / 15 lbs', unit: 'reps',
        description: 'Performing curls with a cable provides constant tension on the biceps through both the concentric and eccentric parts of the movement.',
        videoUrl: 'https://www.youtube.com/embed/NFzTWp2qpiE',
        muscleGroups: ['Biceps Brachii'],
        sets: [{ id: 'lib-cable-curls-s1', exerciseId: 'lib-cable-curls', targetReps: '12-15' }, { id: 'lib-cable-curls-s2', exerciseId: 'lib-cable-curls', targetReps: '12-15' }, { id: 'lib-cable-curls-s3', exerciseId: 'lib-cable-curls', targetReps: '12-15' }],
      },
      {
        id: 'lib-close-grip-bp', name: 'Close-Grip Bench Press', targetWeight: '85 lbs / 45 lbs', unit: 'reps',
        description: 'A bench press variation with a narrower grip, which shifts the emphasis from the chest to the triceps. A great triceps mass builder.',
        videoUrl: 'https://www.youtube.com/embed/nEF0bv2FW94',
        muscleGroups: ['Triceps', 'Pectoralis Major', 'Deltoids'],
        sets: [{ id: 'lib-close-grip-bp-s1', exerciseId: 'lib-close-grip-bp', targetReps: '6-10' }, { id: 'lib-close-grip-bp-s2', exerciseId: 'lib-close-grip-bp', targetReps: '6-10' }, { id: 'lib-close-grip-bp-s3', exerciseId: 'lib-close-grip-bp', targetReps: '6-10' }],
      },
      {
        id: 'lib-tri-pushdowns', name: 'Triceps Pushdowns (Rope or Bar)', targetWeight: '40 lbs / 20 lbs', unit: 'reps',
        description: 'A common triceps isolation exercise on a cable machine. A rope allows for greater range of motion, while a bar allows for heavier weight.',
        videoUrl: 'https://www.youtube.com/embed/2-LAMcpzODU',
        muscleGroups: ['Triceps Brachii'],
        sets: [{ id: 'lib-tri-pushdowns-s1', exerciseId: 'lib-tri-pushdowns', targetReps: '10-15' }, { id: 'lib-tri-pushdowns-s2', exerciseId: 'lib-tri-pushdowns', targetReps: '10-15' }, { id: 'lib-tri-pushdowns-s3', exerciseId: 'lib-tri-pushdowns', targetReps: '10-15' }],
      },
      {
        id: 'lib-skull-crushers', name: 'Skull Crushers (Lying Triceps Extensions)', targetWeight: '45 lbs / 25 lbs', unit: 'reps',
        description: 'Lying on a bench, you lower a barbell or dumbbells from above your chest towards your forehead, then extend back up.',
        videoUrl: 'https://www.youtube.com/embed/d_KZxkY_0cM',
        muscleGroups: ['Triceps Brachii'],
        sets: [{ id: 'lib-skull-crushers-s1', exerciseId: 'lib-skull-crushers', targetReps: '8-12' }, { id: 'lib-skull-crushers-s2', exerciseId: 'lib-skull-crushers', targetReps: '8-12' }, { id: 'lib-skull-crushers-s3', exerciseId: 'lib-skull-crushers', targetReps: '8-12' }],
      },
      {
        id: 'lib-overhead-tri-ext', name: 'Overhead Triceps Extensions', targetWeight: '20 lbs / 10 lbs', unit: 'reps',
        description: 'Can be done seated or standing with a dumbbell or cable. This exercise fully stretches the long head of the triceps.',
        videoUrl: 'https://www.youtube.com/embed/3_h-02AqPA4',
        muscleGroups: ['Triceps Brachii'],
        sets: [{ id: 'lib-overhead-tri-ext-s1', exerciseId: 'lib-overhead-tri-ext', targetReps: '10-15' }, { id: 'lib-overhead-tri-ext-s2', exerciseId: 'lib-overhead-tri-ext', targetReps: '10-15' }, { id: 'lib-overhead-tri-ext-s3', exerciseId: 'lib-overhead-tri-ext', targetReps: '10-15' }],
      },
      {
        id: 'lib-triceps-dips', name: 'Triceps Dips', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'Can be performed on parallel bars (more difficult) or a bench. A fantastic bodyweight exercise for building triceps mass.',
        videoUrl: 'https://www.youtube.com/embed/0326dy_-CzM',
        muscleGroups: ['Triceps', 'Pectoralis Major', 'Deltoids'],
        sets: [{ id: 'lib-triceps-dips-s1', exerciseId: 'lib-triceps-dips', targetReps: 'To Failure' }, { id: 'lib-triceps-dips-s2', exerciseId: 'lib-triceps-dips', targetReps: 'To Failure' }, { id: 'lib-triceps-dips-s3', exerciseId: 'lib-triceps-dips', targetReps: 'To Failure' }],
      },
      {
        id: 'lib-diamond-push-ups', name: 'Diamond Push-Ups', targetWeight: 'Bodyweight', unit: 'reps',
        description: 'A challenging push-up variation where the hands are placed close together in a diamond shape, intensely targeting the triceps.',
        videoUrl: 'https://www.youtube.com/embed/J0D-5_WNFbU',
        muscleGroups: ['Triceps', 'Pectoralis Major'],
        sets: [{ id: 'lib-diamond-push-ups-s1', exerciseId: 'lib-diamond-push-ups', targetReps: 'To Failure' }, { id: 'lib-diamond-push-ups-s2', exerciseId: 'lib-diamond-push-ups', targetReps: 'To Failure' }, { id: 'lib-diamond-push-ups-s3', exerciseId: 'lib-diamond-push-ups', targetReps: 'To Failure' }],
      },
      {
        id: 'lib-wrist-curls', name: 'Wrist Curls', targetWeight: '15 lbs / 5 lbs', unit: 'reps',
        description: 'An isolation exercise for the forearm flexors, crucial for grip strength. Performed by curling a barbell or dumbbell with just the wrist.',
        videoUrl: 'https://www.youtube.com/embed/NoO4ol8c4Yo',
        muscleGroups: ['Forearm Flexors'],
        sets: [{ id: 'lib-wrist-curls-s1', exerciseId: 'lib-wrist-curls', targetReps: '15-20' }, { id: 'lib-wrist-curls-s2', exerciseId: 'lib-wrist-curls', targetReps: '15-20' }, { id: 'lib-wrist-curls-s3', exerciseId: 'lib-wrist-curls', targetReps: '15-20' }],
      },
      {
        id: 'lib-reverse-wrist-curls', name: 'Reverse Wrist Curls', targetWeight: '10 lbs / 5 lbs', unit: 'reps',
        description: 'The opposite of wrist curls, targeting the forearm extensors by curling the weight upwards with palms facing down.',
        videoUrl: 'https://www.youtube.com/embed/zV_L2BFa3yY',
        muscleGroups: ['Forearm Extensors'],
        sets: [{ id: 'lib-reverse-wrist-curls-s1', exerciseId: 'lib-reverse-wrist-curls', targetReps: '15-20' }, { id: 'lib-reverse-wrist-curls-s2', exerciseId: 'lib-reverse-wrist-curls', targetReps: '15-20' }, { id: 'lib-reverse-wrist-curls-s3', exerciseId: 'lib-reverse-wrist-curls', targetReps: '15-20' }],
      },
      {
        id: 'lib-farmers-walk', name: "Farmer's Walk", targetWeight: '50 lbs / 25 lbs per hand', unit: 'reps',
        description: 'A full-body exercise that heavily taxes grip strength. Simply pick up heavy dumbbells or kettlebells and walk for a set distance or time.',
        videoUrl: 'https://www.youtube.com/embed/Fkzk_RqlYig',
        muscleGroups: ['Forearms', 'Traps', 'Core', 'Legs'],
        sets: [{ id: 'lib-farmers-walk-s1', exerciseId: 'lib-farmers-walk', targetReps: 'for distance/time' }, { id: 'lib-farmers-walk-s2', exerciseId: 'lib-farmers-walk', targetReps: 'for distance/time' }, { id: 'lib-farmers-walk-s3', exerciseId: 'lib-farmers-walk', targetReps: 'for distance/time' }],
      },
      {
        id: 'lib-plank', name: 'Plank', targetWeight: 'Bodyweight', unit: 's', isCore: true,
        description: 'An isometric core exercise where you hold a push-up-like position on your forearms, maintaining a straight line from head to heels.',
        videoUrl: 'https://www.youtube.com/embed/pDafg-Bv-s8',
        muscleGroups: ['Rectus Abdominis', 'Transverse Abdominis', 'Obliques'],
        sets: [{ id: 'lib-plank-s1', exerciseId: 'lib-plank', targetReps: '30-60', unit: 's' }, { id: 'lib-plank-s2', exerciseId: 'lib-plank', targetReps: '30-60', unit: 's' }, { id: 'lib-plank-s3', exerciseId: 'lib-plank', targetReps: '30-60', unit: 's' }],
      },
      {
        id: 'lib-crunches', name: 'Crunches', targetWeight: 'Bodyweight', unit: 'reps', isCore: true,
        description: 'A classic abdominal exercise that targets the upper rectus abdominis by curling your torso towards your knees.',
        videoUrl: 'https://www.youtube.com/embed/Xyd_fa5zoEU',
        muscleGroups: ['Rectus Abdominis'],
        sets: [{ id: 'lib-crunches-s1', exerciseId: 'lib-crunches', targetReps: '15-25' }, { id: 'lib-crunches-s2', exerciseId: 'lib-crunches', targetReps: '15-25' }, { id: 'lib-crunches-s3', exerciseId: 'lib-crunches', targetReps: '15-25' }],
      },
      {
        id: 'lib-leg-raises', name: 'Leg Raises', targetWeight: 'Bodyweight', unit: 'reps', isCore: true,
        description: 'Lying on your back, you raise your legs towards the ceiling, targeting the lower abs and hip flexors.',
        videoUrl: 'https://www.youtube.com/embed/l4kQd9eWclE',
        muscleGroups: ['Lower Rectus Abdominis', 'Hip Flexors'],
        sets: [{ id: 'lib-leg-raises-s1', exerciseId: 'lib-leg-raises', targetReps: '15-20' }, { id: 'lib-leg-raises-s2', exerciseId: 'lib-leg-raises', targetReps: '15-20' }, { id: 'lib-leg-raises-s3', exerciseId: 'lib-leg-raises', targetReps: '15-20' }],
      },
      {
        id: 'lib-russian-twists', name: 'Russian Twists', targetWeight: 'Bodyweight or 10 lbs / 5 lbs', unit: 'reps', isCore: true,
        description: 'A seated core exercise that targets the obliques by twisting your torso from side to side, often with a weight.',
        videoUrl: 'https://www.youtube.com/embed/wkD8rjkodUI',
        muscleGroups: ['Obliques', 'Rectus Abdominis'],
        sets: [{ id: 'lib-russian-twists-s1', exerciseId: 'lib-russian-twists', targetReps: '15-20 per side' }, { id: 'lib-russian-twists-s2', exerciseId: 'lib-russian-twists', targetReps: '15-20 per side' }, { id: 'lib-russian-twists-s3', exerciseId: 'lib-russian-twists', targetReps: '15-20 per side' }],
      },
      {
        id: 'lib-hanging-knee-raises', name: 'Hanging Knee Raises', targetWeight: 'Bodyweight', unit: 'reps', isCore: true,
        description: 'A challenging exercise from a hanging position where you raise your knees to your chest, targeting the lower abs.',
        videoUrl: 'https://www.youtube.com/embed/hdng3Nm1x_E',
        muscleGroups: ['Lower Rectus Abdominis', 'Obliques', 'Hip Flexors'],
        sets: [{ id: 'lib-hanging-knee-raises-s1', exerciseId: 'lib-hanging-knee-raises', targetReps: 'To Failure' }, { id: 'lib-hanging-knee-raises-s2', exerciseId: 'lib-hanging-knee-raises', targetReps: 'To Failure' }, { id: 'lib-hanging-knee-raises-s3', exerciseId: 'lib-hanging-knee-raises', targetReps: 'To Failure' }],
      },
      {
        id: 'lib-hanging-leg-raises', name: 'Hanging Leg Raises', targetWeight: 'Bodyweight', unit: 'reps', isCore: true,
        description: 'A more advanced version of the hanging knee raise where you keep your legs straight, increasing the difficulty.',
        videoUrl: 'https://www.youtube.com/embed/Pr1ieGZ5atk',
        muscleGroups: ['Lower Rectus Abdominis', 'Obliques', 'Hip Flexors'],
        sets: [{ id: 'lib-hanging-leg-raises-s1', exerciseId: 'lib-hanging-leg-raises', targetReps: 'To Failure' }, { id: 'lib-hanging-leg-raises-s2', exerciseId: 'lib-hanging-leg-raises', targetReps: 'To Failure' }, { id: 'lib-hanging-leg-raises-s3', exerciseId: 'lib-hanging-leg-raises', targetReps: 'To Failure' }],
      },
      {
        id: 'lib-ab-rollouts', name: 'Ab Rollouts', targetWeight: 'Bodyweight', unit: 'reps', isCore: true,
        description: 'An advanced core exercise using an ab wheel. You roll the wheel forward from a kneeling position, extending your body, and then roll back.',
        videoUrl: 'https://www.youtube.com/embed/0s_6O_d_G2A',
        muscleGroups: ['Rectus Abdominis', 'Transverse Abdominis', 'Obliques'],
        sets: [{ id: 'lib-ab-rollouts-s1', exerciseId: 'lib-ab-rollouts', targetReps: '8-12' }, { id: 'lib-ab-rollouts-s2', exerciseId: 'lib-ab-rollouts', targetReps: '8-12' }, { id: 'lib-ab-rollouts-s3', exerciseId: 'lib-ab-rollouts', targetReps: '8-12' }],
      },
      {
        id: 'lib-cable-woodchops', name: 'Cable Woodchops', targetWeight: '20 lbs / 10 lbs', unit: 'reps', isCore: true,
        description: 'A functional core exercise that mimics a chopping motion with a cable, targeting the obliques and improving rotational strength.',
        videoUrl: 'https://www.youtube.com/embed/pAplQXk3dkU',
        muscleGroups: ['Obliques', 'Rectus Abdominis'],
        sets: [{ id: 'lib-cable-woodchops-s1', exerciseId: 'lib-cable-woodchops', targetReps: '10-15 per side' }, { id: 'lib-cable-woodchops-s2', exerciseId: 'lib-cable-woodchops', targetReps: '10-15 per side' }, { id: 'lib-cable-woodchops-s3', exerciseId: 'lib-cable-woodchops', targetReps: '10-15 per side' }],
      },
      {
        id: 'lib-side-plank', name: 'Side Plank', targetWeight: 'Bodyweight', unit: 's', isCore: true,
        description: 'An isometric exercise where you support your body on one forearm, targeting the obliques and improving core stability.',
        videoUrl: 'https://www.youtube.com/embed/Z64142k_S84',
        muscleGroups: ['Obliques', 'Transverse Abdominis'],
        sets: [{ id: 'lib-side-plank-s1', exerciseId: 'lib-side-plank', targetReps: '30-45', unit: 's' }, { id: 'lib-side-plank-s2', exerciseId: 'lib-side-plank', targetReps: '30-45', unit: 's' }, { id: 'lib-side-plank-s3', exerciseId: 'lib-side-plank', targetReps: '30-45', unit: 's' }],
      },
      {
        id: 'lib-bicycle-crunches', name: 'Bicycle Crunches', targetWeight: 'Bodyweight', unit: 'reps', isCore: true,
        description: 'A dynamic crunch variation where you bring opposite knee to opposite elbow, engaging both the upper and lower abs as well as the obliques.',
        videoUrl: 'https://www.youtube.com/embed/Iwyvozckjak',
        muscleGroups: ['Rectus Abdominis', 'Obliques'],
        sets: [{ id: 'lib-bicycle-crunches-s1', exerciseId: 'lib-bicycle-crunches', targetReps: '20-30 total' }, { id: 'lib-bicycle-crunches-s2', exerciseId: 'lib-bicycle-crunches', targetReps: '20-30 total' }, { id: 'lib-bicycle-crunches-s3', exerciseId: 'lib-bicycle-crunches', targetReps: '20-30 total' }],
      },
      {
        id: 'lib-flutter-kicks', name: 'Flutter Kicks', targetWeight: 'Bodyweight', unit: 's', isCore: true,
        description: 'Lying on your back with legs extended, you perform small, rapid up-and-down kicks, targeting the lower abs.',
        videoUrl: 'https://www.youtube.com/embed/ANVdMDa-dGo',
        muscleGroups: ['Lower Rectus Abdominis'],
        sets: [{ id: 'lib-flutter-kicks-s1', exerciseId: 'lib-flutter-kicks', targetReps: '30-60', unit: 's' }, { id: 'lib-flutter-kicks-s2', exerciseId: 'lib-flutter-kicks', targetReps: '30-60', unit: 's' }, { id: 'lib-flutter-kicks-s3', exerciseId: 'lib-flutter-kicks', targetReps: '30-60', unit: 's' }],
      },
      {
        id: 'lib-v-ups', name: 'V-Ups', targetWeight: 'Bodyweight', unit: 'reps', isCore: true,
        description: 'A challenging ab exercise where you lie on your back and simultaneously raise your straight legs and torso, touching your toes in a "V" shape.',
        videoUrl: 'https://www.youtube.com/embed/iP2fjvG_xU8',
        muscleGroups: ['Rectus Abdominis', 'Obliques'],
        sets: [{ id: 'lib-v-ups-s1', exerciseId: 'lib-v-ups', targetReps: '10-15' }, { id: 'lib-v-ups-s2', exerciseId: 'lib-v-ups', targetReps: '10-15' }, { id: 'lib-v-ups-s3', exerciseId: 'lib-v-ups', targetReps: '10-15' }],
      },
      {
        id: 'lib-decline-crunches', name: 'Decline Crunches', targetWeight: 'Bodyweight', unit: 'reps', isCore: true,
        description: 'Performing crunches on a decline bench increases the range of motion and difficulty, further targeting the rectus abdominis.',
        videoUrl: 'https://www.youtube.com/embed/W_iJgscG_gA',
        muscleGroups: ['Rectus Abdominis'],
        sets: [{ id: 'lib-decline-crunches-s1', exerciseId: 'lib-decline-crunches', targetReps: '15-20' }, { id: 'lib-decline-crunches-s2', exerciseId: 'lib-decline-crunches', targetReps: '15-20' }, { id: 'lib-decline-crunches-s3', exerciseId: 'lib-decline-crunches', targetReps: '15-20' }],
      },
      {
        id: 'lib-cable-crunches', name: 'Cable Crunches', targetWeight: '40 lbs / 20 lbs', unit: 'reps', isCore: true,
        description: 'Kneeling in front of a high pulley with a rope attachment, you crunch your torso downwards against the resistance.',
        videoUrl: 'https://www.youtube.com/embed/F_V_gT-v1tA',
        muscleGroups: ['Rectus Abdominis'],
        sets: [{ id: 'lib-cable-crunches-s1', exerciseId: 'lib-cable-crunches', targetReps: '15-20' }, { id: 'lib-cable-crunches-s2', exerciseId: 'lib-cable-crunches', targetReps: '15-20' }, { id: 'lib-cable-crunches-s3', exerciseId: 'lib-cable-crunches', targetReps: '15-20' }],
      },
      {
        id: 'lib-pallof-press', name: 'Pallof Press', targetWeight: '20 lbs / 10 lbs', unit: 'reps', isCore: true,
        description: 'An anti-rotation exercise where you stand sideways to a cable machine and press the handle straight out from your chest, resisting the rotational force.',
        videoUrl: 'https://www.youtube.com/embed/protection_and_safety_are_paramount',
        muscleGroups: ['Obliques', 'Transverse Abdominis'],
        sets: [{ id: 'lib-pallof-press-s1', exerciseId: 'lib-pallof-press', targetReps: '10-12 per side' }, { id: 'lib-pallof-press-s2', exerciseId: 'lib-pallof-press', targetReps: '10-12 per side' }, { id: 'lib-pallof-press-s3', exerciseId: 'lib-pallof-press', targetReps: '10-12 per side' }],
      },
    ],
  }];

export const defaultNamedPlans: NamedWorkoutPlan[] = [
  {
    id: 'jeff-nippard-plan',
    name: "Jeff Nippard's PPL/Upper/Lower",
    description: "A 5-day split focusing on Push, Pull, Legs, Upper, and Arms/Shoulders for comprehensive development.",
    plan: jeffNippardPlan,
    isActive: true,
  },
  {
    id: 'optimized-gym-calisthenics-blended-plan',
    name: 'Optimized Gym & Calisthenics Blend',
    description: 'A balanced plan incorporating gym equipment and calisthenics for strength, skill, and conditioning, with integrated core work.',
    plan: optimizedGymCalisthenicsPlan,
    isActive: false,
  },
  {
    id: 'ppl-hybrid-split',
    name: 'Hybrid PPL/Upper-Lower Split',
    description: 'A 5-day PPL/Upper/Lower split combining calisthenics and machine work for balanced strength and muscle growth.',
    plan: pplHybridPlan,
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


// Helper function to get all unique exercises from all default plans and the library.
export const getAllExercisesFromPlan = (): Exercise[] => {
  const allExercisesMap = new Map<string, Exercise>();
  
  // Always search all default plans
  defaultNamedPlans.forEach(namedPlan => {
    namedPlan.plan.forEach(day => {
      day.exercises.forEach(exercise => {
        if (!allExercisesMap.has(exercise.id)) {
          allExercisesMap.set(exercise.id, exercise);
        }
      });
    });
  });

  // Always include exercises from the standalone library
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
export const weeklyPlan: WeeklyPlan = pplHybridPlan; 

export { pplHybridPlan as defaultStrengthPlan };
