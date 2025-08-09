'use server';
/**
 * @fileOverview AI-powered recommendations for the next session's weight and reps based on recent performance.
 *
 * - nextSessionRecommendation - A function that handles the next session recommendation process.
 * - NextSessionRecommendationInput - The input type for the function.
 * - NextSessionRecommendationOutput - The return type for the function.
 */

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

const prompt = ai.definePrompt({
  name: 'nextSessionRecommendationPrompt',
  input: {schema: NextSessionRecommendationInputSchema},
  output: {schema: NextSessionRecommendationOutputSchema},
  prompt: `You are an expert personal training AI. Analyze the recent performance for the exercise: {{{exerciseName}}}.
The user's goal is {{#if userGoal}}'{{{userGoal}}}'{{else}}'general strength and hypertrophy through progressive overload'{{/if}}.
{{#if targetProgressionRate}}The user aims for a progression of '{{{targetProgressionRate}}}'.{{/if}}

Recent Performance Data:
{{#each recentPerformance}}
- Date: {{{date}}}, Weight: {{{weight}}}, Reps per Set: {{#each repsPerSet}}{{{this}}}{{#unless @last}}, {{/unless}}{{/each}}
{{/each}}

Based on this data, especially the trend over the last 2-4 weeks:
1.  Determine if the user is consistently meeting or exceeding current targets.
2.  Consider if performance is stalling, improving, or declining.
3.  Suggest a specific, actionable weight and rep target for the *next* session for '{{{exerciseName}}}'.
4.  The suggestion should aim for progressive overload. This could mean increasing weight, reps, or sets. Prioritize weight increases if reps are consistently met at good form (assume good form unless data implies struggle).
5.  Provide a concise reasoning for your suggestion, linking it to the performance trend.
6.  If performance is poor or declining, suggest maintaining or slightly reducing weight and focusing on form or hitting rep targets.
7.  Format weight suggestions clearly (e.g., "82.5 kg", "Bodyweight +5kg").
8.  Format rep suggestions clearly (e.g., "3x8-10", "Aim for 10, 9, 8 reps").

Example Output:
{
  "suggestedWeight": "82.5 kg",
  "suggestedReps": "3 sets of 8 reps",
  "reasoning": "Consistently hit 80kg for 3x8. A 2.5kg increase is a good next step for progressive overload."
}
Do not be conversational. Output only the JSON.
`,
});

const nextSessionRecommendationFlow = ai.defineFlow(
  {
    name: 'nextSessionRecommendationFlow',
    inputSchema: NextSessionRecommendationInputSchema,
    outputSchema: NextSessionRecommendationOutputSchema,
  },
  async input => {
    // Ensure recentPerformance is sorted by date if not already
    input.recentPerformance.sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime());
    
    // Optionally, limit to last N entries if too much data is passed.
    // e.g., input.recentPerformance = input.recentPerformance.slice(-8); // last 8 workouts (approx 2-4 weeks for 2-3x/week)

    const {output} = await prompt(input);
    if (!output) {
        throw new Error("AI failed to generate a recommendation.");
    }
    return output;
  }
);
