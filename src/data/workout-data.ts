
import type { WeeklyPlan } from '@/types/workout';

export const weeklyPlan: WeeklyPlan = [
  {
    id: 'monday',
    dayName: 'Monday',
    title: 'Upper Body Push',
    exercises: [
      {
        id: 'mon-ex1', name: 'Incline DB Bench Press', targetWeight: '22.5 kg', unit: 'reps',
        sets: [
          { id: 'mon-ex1-set1', targetReps: 12 },
          { id: 'mon-ex1-set2', targetReps: 10 },
          { id: 'mon-ex1-set3', targetReps: 8 },
        ],
      },
      {
        id: 'mon-ex2', name: 'Smith Machine Incline Press', targetWeight: '17.5 kg', unit: 'reps',
        sets: [
          { id: 'mon-ex2-set1', targetReps: 10 },
          { id: 'mon-ex2-set2', targetReps: 8 },
          { id: 'mon-ex2-set3', targetReps: 8 },
        ],
      },
      {
        id: 'mon-ex3', name: 'Dips', targetWeight: '0 kg (bodyweight)', unit: 'reps',
        sets: [
          { id: 'mon-ex3-set1', targetReps: 8 },
          { id: 'mon-ex3-set2', targetReps: 6 },
          { id: 'mon-ex3-set3', targetReps: 6 },
        ],
      },
      {
        id: 'mon-ex4', name: 'Seated Shoulder Press', targetWeight: '65 kg', unit: 'reps',
        sets: [
          { id: 'mon-ex4-set1', targetReps: 12 },
          { id: 'mon-ex4-set2', targetReps: 10 },
          { id: 'mon-ex4-set3', targetReps: 8 },
        ],
      },
      {
        id: 'mon-ex5', name: 'Cable Fly (rope)', targetWeight: '2nd stack', unit: 'reps',
        sets: [
          { id: 'mon-ex5-set1', targetReps: 12 },
          { id: 'mon-ex5-set2', targetReps: 10 },
          { id: 'mon-ex5-set3', targetReps: 8 },
        ],
      },
      {
        id: 'mon-ex6', name: 'Rear-Delt Cable Fly', targetWeight: '12 kg', unit: 'reps',
        sets: [
          { id: 'mon-ex6-set1', targetReps: 12 },
          { id: 'mon-ex6-set2', targetReps: 12 },
          { id: 'mon-ex6-set3', targetReps: '—' },
        ],
      },
      {
        id: 'mon-ex7', name: 'Triceps Rope Pushdown', targetWeight: '5th stack', unit: 'reps',
        sets: [
          { id: 'mon-ex7-set1', targetReps: '—' },
          { id: 'mon-ex7-set2', targetReps: '—' },
          { id: 'mon-ex7-set3', targetReps: '—' },
        ],
      },
      {
        id: 'mon-ex8', name: 'Core – Plank', unit: 's', isCore: true, notes: 'Duration: 60–75 s',
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
        sets: [
          { id: 'tue-ex1-set1', targetReps: 12 },
          { id: 'tue-ex1-set2', targetReps: 10 },
          { id: 'tue-ex1-set3', targetReps: 8 },
        ],
      },
      {
        id: 'tue-ex2', name: 'Neutral-Grip Pulldown', targetWeight: '11th stack', unit: 'reps', notes: 'Superset A',
        sets: [
          { id: 'tue-ex2-set1', targetReps: 12 },
          { id: 'tue-ex2-set2', targetReps: 10 },
          { id: 'tue-ex2-set3', targetReps: 8 },
        ],
      },
      {
        id: 'tue-ex3', name: 'Face Pulls', targetWeight: 'cable', unit: 'reps', notes: 'Superset B',
        sets: [
          { id: 'tue-ex3-set1', targetReps: 15 },
          { id: 'tue-ex3-set2', targetReps: 13 },
          { id: 'tue-ex3-set3', targetReps: 12 },
        ],
      },
      {
        id: 'tue-ex4', name: 'Half-Kneeling One-Arm Lat Pulldown (each arm)', targetWeight: '5th stack', unit: 'reps',
        sets: [
          { id: 'tue-ex4-set1', targetReps: 12 },
          { id: 'tue-ex4-set2', targetReps: 10 },
          { id: 'tue-ex4-set3', targetReps: 8 },
        ],
      },
      {
        id: 'tue-ex5', name: 'Dumbbell Preacher Curl (each arm)', targetWeight: '10 kg', unit: 'reps',
        sets: [
          { id: 'tue-ex5-set1', targetReps: 12 },
          { id: 'tue-ex5-set2', targetReps: 10 },
          { id: 'tue-ex5-set3', targetReps: 8 },
        ],
      },
      {
        id: 'tue-ex6', name: 'Barbell Preacher Curl', targetWeight: '7.5 kg each side', unit: 'reps',
        sets: [
          { id: 'tue-ex6-set1', targetReps: 12 },
          { id: 'tue-ex6-set2', targetReps: 10 },
          { id: 'tue-ex6-set3', targetReps: 8 },
        ],
      },
      {
        id: 'tue-ex7', name: 'Core – Hanging Leg Raises', unit: 'reps', isCore: true,
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
        sets: [
          { id: 'wed-ex1-set1', targetReps: 12 },
          { id: 'wed-ex1-set2', targetReps: 10 },
          { id: 'wed-ex1-set3', targetReps: 8 },
        ],
      },
      {
        id: 'wed-ex2', name: 'Romanian Deadlift', targetWeight: '15 kg', unit: 'reps', notes: 'Superset B',
        sets: [
          { id: 'wed-ex2-set1', targetReps: 12 },
          { id: 'wed-ex2-set2', targetReps: 10 },
          { id: 'wed-ex2-set3', targetReps: 8 },
        ],
      },
      {
        id: 'wed-ex3', name: 'Leg Press', targetWeight: '60 kg', unit: 'reps',
        sets: [
          { id: 'wed-ex3-set1', targetReps: 12 },
          { id: 'wed-ex3-set2', targetReps: 10 },
          { id: 'wed-ex3-set3', targetReps: 8 },
        ],
      },
      {
        id: 'wed-ex4', name: 'Smith Machine Squats', targetWeight: '22 kg', unit: 'reps',
        sets: [
          { id: 'wed-ex4-set1', targetReps: 12 },
          { id: 'wed-ex4-set2', targetReps: 10 },
          { id: 'wed-ex4-set3', targetReps: 8 },
        ],
      },
      {
        id: 'wed-ex5', name: 'Leg Extension', targetWeight: '25 kg', unit: 'reps',
        sets: [
          { id: 'wed-ex5-set1', targetReps: 15 },
          { id: 'wed-ex5-set2', targetReps: 13 },
          { id: 'wed-ex5-set3', targetReps: 12 },
        ],
      },
      {
        id: 'wed-ex6', name: 'Glute Machine or DB Hip Thrust', targetWeight: '45 kg', unit: 'reps',
        sets: [
          { id: 'wed-ex6-set1', targetReps: 15 },
          { id: 'wed-ex6-set2', targetReps: 13 },
          { id: 'wed-ex6-set3', targetReps: 12 },
        ],
      },
      {
        id: 'wed-ex7', name: 'Calf Raises (Smith or DB)', targetWeight: 'bodyweight or added', unit: 'reps',
        sets: [
          { id: 'wed-ex7-set1', targetReps: 20 },
          { id: 'wed-ex7-set2', targetReps: 18 },
          { id: 'wed-ex7-set3', targetReps: 15 },
        ],
      },
      {
        id: 'wed-ex8', name: 'Core – Ab Wheel Rollouts or Cable Crunches', unit: 'reps', isCore: true,
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
        sets: [
          { id: 'thu-ex1-set1', targetReps: 8 },
          { id: 'thu-ex1-set2', targetReps: 6 },
          { id: 'thu-ex1-set3', targetReps: 6 },
        ],
      },
      {
        id: 'thu-ex2', name: 'Cable Face Pulls', targetWeight: 'before last stack', unit: 'reps',
        sets: [
          { id: 'thu-ex2-set1', targetReps: 12 },
          { id: 'thu-ex2-set2', targetReps: 10 },
          { id: 'thu-ex2-set3', targetReps: 8 },
        ],
      },
      {
        id: 'thu-ex3', name: 'Incline DB Press', targetWeight: '17.5 kg', unit: 'reps',
        sets: [
          { id: 'thu-ex3-set1', targetReps: 12 },
          { id: 'thu-ex3-set2', targetReps: 11 },
          { id: 'thu-ex3-set3', targetReps: 10 },
        ],
      },
      {
        id: 'thu-ex4', name: 'Overhead Triceps Extension', targetWeight: '6th stack', unit: 'reps',
        sets: [
          { id: 'thu-ex4-set1', targetReps: 15 },
          { id: 'thu-ex4-set2', targetReps: 14 },
          { id: 'thu-ex4-set3', targetReps: 12 },
        ],
      },
      {
        id: 'thu-ex5', name: 'DB Lateral Raises', targetWeight: '7.5 kg', unit: 'reps',
        sets: [
          { id: 'thu-ex5-set1', targetReps: 15 },
          { id: 'thu-ex5-set2', targetReps: 14 },
          { id: 'thu-ex5-set3', targetReps: 12 },
        ],
      },
      {
        id: 'thu-ex6', name: 'DB/Smith Romanian Deadlift', targetWeight: '15 kg', unit: 'reps',
        sets: [
          { id: 'thu-ex6-set1', targetReps: 12 },
          { id: 'thu-ex6-set2', targetReps: 10 },
          { id: 'thu-ex6-set3', targetReps: 8 },
        ],
      },
      {
        id: 'thu-ex7', name: 'Russian Twists', targetWeight: '7.5 kgs', unit: 'reps', isCore: true,
        sets: [
          { id: 'thu-ex7-set1', targetReps: 20 },
          { id: 'thu-ex7-set2', targetReps: 20 },
          { id: 'thu-ex7-set3', targetReps: 20 },
        ],
      },
      {
        id: 'thu-ex8', name: 'Conditioning Finisher', isConditioning: true, unit: 'min',
        notes: '10–15 min HIIT (30 s burpees / 30 s rest)',
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
        sets: [
          { id: 'fri-ex1-set1', targetReps: 10 },
          { id: 'fri-ex1-set2', targetReps: 8 },
          { id: 'fri-ex1-set3', targetReps: 9 },
        ],
      },
      {
        id: 'fri-ex2', name: 'Dips', targetWeight: 'bodyweight', unit: 'reps',
        sets: [
          { id: 'fri-ex2-set1', targetReps: 12 },
          { id: 'fri-ex2-set2', targetReps: 10 },
          { id: 'fri-ex2-set3', targetReps: 9 },
        ],
      },
      {
        id: 'fri-ex3', name: 'Advanced Push-Ups', targetWeight: 'bodyweight', unit: 'reps',
        sets: [
          { id: 'fri-ex3-set1', targetReps: 'to failure / 18' },
          { id: 'fri-ex3-set2', targetReps: 'to failure / 14' },
          { id: 'fri-ex3-set3', targetReps: 'to failure / 12' },
        ],
      },
      {
        id: 'fri-ex4', name: 'Bodyweight/Jump Squats', unit: 'reps', targetWeight: 'bodyweight',
        sets: [
          { id: 'fri-ex4-set1', targetReps: 15 },
          { id: 'fri-ex4-set2', targetReps: 13 },
          { id: 'fri-ex4-set3', targetReps: 12 },
        ],
      },
      {
        id: 'fri-ex5', name: 'Hanging Windshield Wipers or L-Sit', unit: 'reps', isCore: true, targetWeight: 'bodyweight',
        sets: [
          { id: 'fri-ex5-set1', targetReps: '10 (or hold)' },
          { id: 'fri-ex5-set2', targetReps: '8 (or hold)' },
          { id: 'fri-ex5-set3', targetReps: '10 (or hold)' },
        ],
      },
      {
        id: 'fri-ex6', name: 'Inverted Rows', unit: 'reps', targetWeight: 'bodyweight',
        sets: [
          { id: 'fri-ex6-set1', targetReps: 10 },
          { id: 'fri-ex6-set2', targetReps: 10 },
          { id: 'fri-ex6-set3', targetReps: 10 },
        ],
      },
      {
        id: 'fri-ex7', name: 'Plank', unit: 's', isCore: true, targetWeight: 'bodyweight',
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
        sets: [
          { id: 'sat-ex1-set1', targetReps: 'Jog 5 min' },
          { id: 'sat-ex1-set2', targetReps: 'Leg swings, 10 ea leg' },
          { id: 'sat-ex1-set3', targetReps: 'A-skips, 20 m' },
        ],
      },
      {
        id: 'sat-ex2', name: 'Accelerations', targetWeight: 'bodyweight', isWarmup: true, isActivity: true,
        sets: [{ id: 'sat-ex2-set1', targetReps: '3 × 20 m all‐out' }],
      },
      {
        id: 'sat-ex3', name: 'Football Match', isMatch: true, isActivity: true, targetWeight: 'N/A',
        sets: [{ id: 'sat-ex3-set1', targetReps: 'Match play (~90 min)' }],
      },
      {
        id: 'sat-ex4', name: 'Cool-Down Jog/Walk', targetWeight: 'bodyweight', isActivity: true,
        sets: [{ id: 'sat-ex4-set1', targetReps: '10 min easy' }],
      },
      {
        id: 'sat-ex5', name: 'Static Stretch', isStretch: true, isActivity: true, targetWeight: 'N/A',
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
        sets: [{ id: 'sun-ex1-set1', targetReps: '1 hour, 10,000 Steps' }],
      },
      {
        id: 'sun-ex2', name: 'Foam-Roll Quads', targetWeight: 'bodyweight', isFoamRoll: true, isRecovery: true,
        sets: [{ id: 'sun-ex2-set1', targetReps: '2 min' }],
      },
      {
        id: 'sun-ex3', name: 'Foam-Roll Hamstrings', targetWeight: 'bodyweight', isFoamRoll: true, isRecovery: true,
        sets: [{ id: 'sun-ex3-set1', targetReps: '2 min' }],
      },
      {
        id: 'sun-ex4', name: 'Foam-Roll Lats', targetWeight: 'bodyweight', isFoamRoll: true, isRecovery: true,
        sets: [{ id: 'sun-ex4-set1', targetReps: '2 min' }],
      },
      {
        id: 'sun-ex5', name: 'PNF Hamstring Stretch', isStretch: true, isRecovery: true, targetWeight: 'N/A',
        sets: [{ id: 'sun-ex5-set1', targetReps: '2 × 30 s ea leg' }],
      },
      {
        id: 'sun-ex6', name: 'PNF Hip-Flexor Stretch', isStretch: true, isRecovery: true, targetWeight: 'N/A',
        sets: [{ id: 'sun-ex6-set1', targetReps: '2 × 30 s ea side' }],
      },
      {
        id: 'sun-ex7', name: 'Shoulder Dislocates', targetWeight: 'band', isStretch: true, isRecovery: true,
        sets: [{ id: 'sun-ex7-set1', targetReps: '15 reps' }],
      },
    ],
  },
];

export const getWorkoutByDay = (dayId: string) => {
  return weeklyPlan.find(day => day.id.toLowerCase() === dayId.toLowerCase());
};

// getDays is not actively used by the modified sidebar, but kept in case it's needed elsewhere.
export const getDays = () => weeklyPlan.map(day => ({ id: day.id, dayName: day.dayName, title: day.title }));
