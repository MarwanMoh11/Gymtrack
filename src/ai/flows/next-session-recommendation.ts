'use server';
/**
 * @fileOverview AI-powered recommendations for the next session's weight and reps based on recent performance.
 *
 * - nextSessionRecommendation - A function that handles the next session recommendation process.
 * - NextSessionRecommendationInput - The input type for the function.
 * - NextSessionRecommendationOutput - The return type for the function.
 */

/*
import {ai} from '@/ai/genkit';
import {z} from 'genkit';

const PerformanceEntrySchema = z.object({
  date: z.string().describe('Date of the workout (YYYY-MM-DD).'),
  weight: z.string().describe('Weight lifted for the exercise (e.g., "80 kg", "bodyweight").'),
  repsPerSet: z.array(z.string()).describe('Array of reps achieved for each set (e.g., ["8", "8", "7"]).'),
});

const NextSessionRecommendationInputSchema = z.object({
  exerciseName: z.string().describe('The name of the exercise.'),
  recentPerformance: z.array(PerformanceEntrySchema).describe('An array of performance entries for the exercise from recent workouts (e.g., last 2-4 weeks).'),
  userGoal: z.string().optional().describe('The user\'s primary training goal (e.g., strength, hypertrophy, endurance). Default to progressive overload for strength/hypertrophy if not specified.'),
  targetProgressionRate: z.string().optional().describe('User-defined target progression rate, if any (e.g., "+2.5kg per week", "+1 rep per set").'),
});
export type NextSessionRecommendationInput = z.infer<typeof NextSessionRecommendationInputSchema>;

const NextSessionRecommendationOutputSchema = z.object({
  suggestedWeight: z.string().describe('The suggested weight for the next session (e.g., "82.5 kg", "Maintain at 80 kg", "Bodyweight").'),
  suggestedReps: z.string().describe('The suggested rep scheme for the next session (e.g., "3 sets of 8-10 reps", "Aim for 9 reps on all sets").'),
  reasoning: z.string().describe('A brief explanation for the recommendation, highlighting how it supports progressive overload based on the trend.'),
});
export type NextSessionRecommendationOutput = z.infer<typeof NextSessionRecommendationOutputSchema>;
*/

// Hand-rolled types to replace z.infer since we commented out zod
export type NextSessionRecommendationInput = {
  exerciseName: string;
  recentPerformance: { date: string; weight: string; repsPerSet: string[] }[];
  userGoal?: string;
  targetProgressionRate?: string;
};

export type NextSessionRecommendationOutput = {
  suggestedWeight: string;
  suggestedReps: string;
  reasoning: string;
};

export async function nextSessionRecommendation(
  input: NextSessionRecommendationInput
): Promise<NextSessionRecommendationOutput> {
  // return nextSessionRecommendationFlow(input);

  // Temporarily disabled to manage costs.
  return new Promise((resolve) => {
    setTimeout(() => {
      resolve({
        suggestedWeight: "AI Suggestion Disabled",
        suggestedReps: "N/A",
        reasoning: "This AI-powered feature has been temporarily disabled to manage operational costs. Please consult your training plan for guidance."
      })
    }, 500);
  });
}

/*
const prompt = ai.definePrompt({
  name: 'nextSessionRecommendationPrompt',
// ...
});

const nextSessionRecommendationFlow = ai.defineFlow(
// ...
);
*/
