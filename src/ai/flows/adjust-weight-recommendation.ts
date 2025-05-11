'use server';

/**
 * @fileOverview AI-powered recommendations for adjusting weight or reps based on the user's logged performance.
 *
 * - adjustWeightRecommendation - A function that handles the weight adjustment recommendation process.
 * - AdjustWeightRecommendationInput - The input type for the adjustWeightRecommendation function.
 * - AdjustWeightRecommendationOutput - The return type for the adjustWeightRecommendation function.
 */

import {ai} from '@/ai/genkit';
import {z} from 'genkit';

const AdjustWeightRecommendationInputSchema = z.object({
  exerciseName: z.string().describe('The name of the exercise.'),
  previousWeight: z.string().describe('The weight used in the previous workout for the exercise.'),
  previousReps: z.string().describe('The number of reps performed in the previous workout for the exercise, for each set.'),
  currentReps: z.string().describe('The number of reps performed in the current workout for the exercise, for each set.'),
  userGoal: z.string().describe('The user goal (e.g., strength, hypertrophy, endurance).'),
});
export type AdjustWeightRecommendationInput = z.infer<
  typeof AdjustWeightRecommendationInputSchema
>;

const AdjustWeightRecommendationOutputSchema = z.object({
  recommendation: z
    .string()
    .describe(
      'A recommendation for adjusting the weight or reps for the next workout, based on the user performance and goal.'
    ),
});
export type AdjustWeightRecommendationOutput = z.infer<
  typeof AdjustWeightRecommendationOutputSchema
>;

export async function adjustWeightRecommendation(
  input: AdjustWeightRecommendationInput
): Promise<AdjustWeightRecommendationOutput> {
  return adjustWeightRecommendationFlow(input);
}

const prompt = ai.definePrompt({
  name: 'adjustWeightRecommendationPrompt',
  input: {schema: AdjustWeightRecommendationInputSchema},
  output: {schema: AdjustWeightRecommendationOutputSchema},
  prompt: `You are a personal trainer providing recommendations on how to adjust weight and reps for the next workout, so users can achieve progressive overload.

  Exercise Name: {{{exerciseName}}}
  Previous Weight: {{{previousWeight}}}
  Previous Reps: {{{previousReps}}}
  Current Reps: {{{currentReps}}}
  User Goal: {{{userGoal}}}

  Based on the user's performance in the current workout compared to the previous workout, and the user's stated goal, provide a recommendation for adjusting the weight or reps for the next workout.
  The response should be concise and actionable.
  Focus on a single clear recommendation.
  Do not ask clarifying questions.
  If the user's current reps are above their previous reps, suggest increasing weight by a small increment.
  If the user's current reps are equal to their previous reps, suggest maintaining weight but focusing on improving form.
  If the user's current reps are below their previous reps, suggest decreasing weight slightly or maintaining weight and focusing on completing the target reps.
`,
});

const adjustWeightRecommendationFlow = ai.defineFlow(
  {
    name: 'adjustWeightRecommendationFlow',
    inputSchema: AdjustWeightRecommendationInputSchema,
    outputSchema: AdjustWeightRecommendationOutputSchema,
  },
  async input => {
    const {output} = await prompt(input);
    return output!;
  }
);
