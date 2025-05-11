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
  targetWeight?: string;
  sets: SetData[];
  notes?: string;
  isCore?: boolean;
  isConditioning?: boolean;
  isWarmup?: boolean;
  isMatch?: boolean;
  isActivity?: boolean; // General category for non-lifting activities
  isStretch?: boolean;
  isFoamRoll?: boolean;
  unit?: 'reps' | 's' | 'min'; // Default unit for exercise if not specified per set
};

export type WorkoutDay = {
  id: string; // e.g., "monday"
  dayName: string; // e.g., "Monday"
  title: string;
  exercises: Exercise[];
  notes?: string; // For overall day notes like circuit instructions
};

export type WeeklyPlan = WorkoutDay[];

export type LoggedSetData = {
  reps?: string | number;
  weight?: string;
  isCompleted: boolean;
};

export type LoggedExerciseData = {
  [setId: string]: LoggedSetData;
};

export type DailyLog = {
  [exerciseId: string]: LoggedExerciseData;
};
