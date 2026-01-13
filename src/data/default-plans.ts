import { NamedWorkoutPlan, WeeklyPlan, WorkoutDay } from '../types/workout';
import { globalExercises } from './global-exercises';

// Helper to create a plan exercise from a global ID
const createPlanExercise = (
  globalId: string,
  setsCount: number,
  reps: string,
  weight?: string
) => {
  const globalEx = globalExercises.find(e => e.id === globalId);
  if (!globalEx) {
    console.warn(`Exercise ${globalId} not found in global library`);
    // Fallback stub to prevent crashes during dev/transition
    return {
      id: `${globalId}-${Math.random().toString(36).substr(2, 9)}`,
      globalExerciseId: globalId,
      name: 'Unknown Exercise',
      sets: Array(setsCount).fill(0).map((_, i) => ({
        id: `set-${i}-${Math.random().toString(36).substr(2, 9)}`,
        exerciseId: `${globalId}`,
        targetReps: reps,
        targetWeight: weight || '0',
        unit: 'reps' as const
      })),
      unit: 'reps' as const
    };
  }

  return {
    id: `${globalId}-${Math.random().toString(36).substr(2, 9)}`,
    globalExerciseId: globalId,
    name: globalEx.name,
    targetWeight: weight || '',
    sets: Array(setsCount).fill(0).map((_, i) => ({
      id: `set-${i}-${Math.random().toString(36).substr(2, 9)}`,
      exerciseId: `${globalId}`,
      targetReps: reps,
      targetWeight: weight || '0',
      unit: globalEx.defaultUnit
    })),
    // Denormalized data
    category: globalEx.category,
    muscleGroups: globalEx.muscleGroups,
    description: globalEx.description || '',
    videoUrl: globalEx.videoUrl || '',
    unit: globalEx.defaultUnit
  };
};

const pushPullLegs: WeeklyPlan = [
  {
    id: 'day-1-push',
    dayName: 'Monday',
    title: 'Push (Chest/Shoulders/Tri)',
    mapsToActualDayOfWeek: 1,
    exercises: [
      createPlanExercise('barbell-bench-press', 3, '8-12', '60 kg'),
      createPlanExercise('overhead-press', 3, '8-12', '40 kg'),
      createPlanExercise('incline-dumbbell-press', 3, '10-12', '20 kg'),
      createPlanExercise('dumbbell-lateral-raise', 3, '12-15', '10 kg'),
      createPlanExercise('tricep-pushdown', 3, '12-15', 'Stack 5'),
    ]
  },
  {
    id: 'day-2-pull',
    dayName: 'Tuesday',
    title: 'Pull (Back/Bi)',
    mapsToActualDayOfWeek: 2,
    exercises: [
      createPlanExercise('deadlift', 3, '5', '100 kg'),
      createPlanExercise('pull-up', 3, 'Failure', 'BW'),
      createPlanExercise('barbell-row', 3, '8-10', '60 kg'),
      createPlanExercise('face-pull', 3, '15-20', 'Stack 4'),
      createPlanExercise('barbell-curl', 3, '10-12', '30 kg'),
    ]
  },
  {
    id: 'day-3-legs',
    dayName: 'Wednesday',
    title: 'Legs',
    mapsToActualDayOfWeek: 3,
    exercises: [
      createPlanExercise('barbell-back-squat', 3, '6-8', '80 kg'),
      createPlanExercise('romanian-deadlift', 3, '8-10', '70 kg'),
      createPlanExercise('leg-press', 3, '10-12', '150 kg'),
      createPlanExercise('leg-extension', 3, '12-15', 'Stack 8'),
      createPlanExercise('lying-leg-curl', 3, '12-15', 'Stack 6'),
      createPlanExercise('plank', 3, '60', 'BW'),
    ]
  },
  { id: 'day-4-rest', dayName: 'Thursday', title: 'Rest / Mobility', exercises: [], isRecovery: true },
  {
    id: 'day-5-upper',
    dayName: 'Friday',
    title: 'Upper Body',
    mapsToActualDayOfWeek: 5,
    exercises: [
      createPlanExercise('barbell-bench-press', 3, '8-12', '60 kg'),
      createPlanExercise('lat-pulldown', 3, '10-12', 'Stack 10'),
      createPlanExercise('chest-dip', 3, 'Failure', 'BW'),
      createPlanExercise('seated-cable-row', 3, '10-12', 'Stack 10'),
      createPlanExercise('dumbbell-lateral-raise', 3, '15', '10 kg'),
    ]
  },
  {
    id: 'day-6-lower',
    dayName: 'Saturday',
    title: 'Lower Body',
    mapsToActualDayOfWeek: 6,
    exercises: [
      createPlanExercise('barbell-back-squat', 3, '6-8', '80 kg'),
      createPlanExercise('bulgarian-split-squat', 3, '10', '15 kg'),
      createPlanExercise('box-jump', 3, '8', '24 inch'),
    ]
  },
  { id: 'day-7-rest', dayName: 'Sunday', title: 'Rest', exercises: [], isRecovery: true },
];

export const defaultNamedPlans: NamedWorkoutPlan[] = [
  {
    id: 'ppl-classic',
    name: 'Classic Push/Pull/Legs',
    description: 'A moderate volume, high frequency split for muscle growth.',
    isActive: true,
    plan: pushPullLegs
  }
];
