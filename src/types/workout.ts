
export type SetData = {
  targetReps: string | number;
  targetWeight?: string;
  unit?: 'reps' | 's' | 'min';
  id: string;
  exerciseId?: string; // Add exerciseId to associate set with its parent
  notes?: string;
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
  isSkill?: boolean; 
  isMobility?: boolean; 
  unit?: 'reps' | 's' | 'min';
};

export type WorkoutDay = {
  id: string;
  dayName: string;
  title: string;
  exercises: Exercise[];
  notes?: string;
  mapsToActualDayOfWeek?: number; // 0 for Sunday, 1 for Monday, etc. (-1 or undefined for unassigned)
  isRecovery?: boolean; 
  isConditioning?: boolean; 
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

// Represents the entire data structure for a user in Firestore
export type UserData = {
  id: string;
  onboardingStatus: 'needs_plan_selection' | 'completed';
  plans: NamedWorkoutPlan[];
  // other top-level user settings can go here
};
