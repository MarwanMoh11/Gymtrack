
export type SetData = {
  targetReps: string | number;
  targetWeight?: string;
  loggedReps?: string | number;
  loggedWeight?: string;
  unit?: 'reps' | 's' | 'min';
  isCompleted?: boolean;
  id: string;
};

export type Exercise = {
  id: string;
  name: string;
  targetWeight?: string; // Default/base target weight for the exercise plan
  sets: SetData[];
  notes?: string;
  description?: string;
  videoUrl?: string;
  muscleGroups?: string[];
  isCore?: boolean;
  isConditioning?: boolean;
  isWarmup?: boolean;
  isMatch?: boolean;
  isActivity?: boolean;
  isStretch?: boolean;
  isFoamRoll?: boolean;
  isRecovery?: boolean;
  unit?: 'reps' | 's' | 'min';
};

export type WorkoutDay = {
  id: string;
  dayName: string;
  title: string;
  exercises: Exercise[];
  notes?: string;
};

export type WeeklyPlan = WorkoutDay[];

export type LoggedSetData = {
  reps?: string | number;
  weight?: string; // The actual weight logged for this specific set instance
  isCompleted: boolean;
};

export type LoggedExerciseData = {
  [setId: string]: LoggedSetData;
};

export type DailyLog = {
  [exerciseId: string]: LoggedExerciseData;
};

// For the AddExerciseModal
export type NewSetData = {
  id: string; // temporary client-side ID
  targetReps: string;
  targetWeight: string;
  unit: 'reps' | 's' | 'min';
};
