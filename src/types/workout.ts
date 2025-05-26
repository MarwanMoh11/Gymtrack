
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
  isSkill?: boolean; // New flag for skill work
  isMobility?: boolean; // New flag for mobility work
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

export type NamedWorkoutPlan = {
  id: string; // Unique ID for the plan (e.g., 'default-strength', 'calisthenics-beast')
  name: string; // User-friendly name (e.g., "Original Strength Plan", "Calisthenics Beast")
  plan: WeeklyPlan; // The actual array of WorkoutDay
  isActive: boolean; // Only one plan can be active at a time
  description?: string; // Optional description of the plan
};

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

