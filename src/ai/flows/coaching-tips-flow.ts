'use server';
/**
 * @fileOverview AI-powered general coaching tips based on recent workout consistency and performance trends.
 *
 * - getCoachingTip - A function that handles generating a coaching tip.
 * - CoachingTipsInput - The input type for the function.
 * - CoachingTipsOutput - The return type for the function.
 */

import {ai} from '@/ai/genkit';
import {z} from 'genkit';

const LogSummarySchema = z.object({
  date: z.string().describe('Date of the workout (YYYY-MM-DD).'),
  exercisesCompleted: z.number().describe('Number of distinct exercises logged as completed on this day.'),
  setsCompleted: z.number().describe('Total number of sets marked as completed on this day.'),
});

const CoachingTipsInputSchema = z.object({
  recentLogs: z.array(LogSummarySchema).describe('A summary of workout logs from the last 2-4 weeks.'),
  streakData: z.object({
    current: z.number().describe('Current workout streak in days.'),
    longest: z.number().describe('Longest workout streak achieved in days.'),
  }).describe('User\'s current and longest workout streaks.'),
  userGoal: z.string().optional().default('General strength and hypertrophy with progressive overload.').describe('The user\'s primary training goal.'),
});
export type CoachingTipsInput = z.infer<typeof CoachingTipsInputSchema>;

const CoachingTipsOutputSchema = z.object({
  tip: z.string().describe('A concise, actionable coaching tip based on recent activity and goals. Should be encouraging and offer general advice like considering deloads, intensity changes, or praising consistency.'),
});
export type CoachingTipsOutput = z.infer<typeof CoachingTipsOutputSchema>;

export async function getCoachingTip(input: CoachingTipsInput): Promise<CoachingTipsOutput> {
  // Filter out days with 0 sets completed before sending to AI, unless recentLogs is empty
  const meaningfulLogs = input.recentLogs.filter(log => log.setsCompleted > 0);
  const inputToSend = {
    ...input,
    recentLogs: meaningfulLogs.length > 0 ? meaningfulLogs : input.recentLogs, // Send original if filtering makes it empty
  };
  return coachingTipsFlow(inputToSend);
}

const prompt = ai.definePrompt({
  name: 'coachingTipsPrompt',
  input: {schema: CoachingTipsInputSchema},
  output: {schema: CoachingTipsOutputSchema},
  prompt: `You are an encouraging and insightful personal training AI coach. Analyze the user's recent workout activity and streaks to provide a helpful, general coaching tip. The user's goal is '{{{userGoal}}}'.

Workout Streaks:
- Current: {{{streakData.current}}} days
- Longest: {{{streakData.longest}}} days

Recent Workout Summary (last 2-4 weeks):
{{#if recentLogs.length}}
{{#each recentLogs}}
- Date: {{{date}}}, Exercises Completed: {{{exercisesCompleted}}}, Sets Completed: {{{setsCompleted}}}
{{/each}}
{{else}}
- No workouts logged recently.
{{/if}}

Based on this information:
1.  Acknowledge their consistency or lack thereof, using the streak data and log frequency.
2.  Look for patterns: Are they consistently working out? Are the number of sets/exercises consistent?
3.  Provide *one* concise, actionable, and encouraging coaching tip.
4.  Tips should be *general* guidance. Examples:
    - If consistency is good: Praise it, suggest maintaining focus or considering a small intensity increase if appropriate.
    - If consistency is poor: Encourage getting back on track, suggest starting small.
    - If logs show activity but streaks are low: Maybe suggest scheduling workouts.
    - If progress seems okay (based on consistency): "Keep up the great work!" or "Focus on form this week."
    - Consider suggesting a deload *only if* there's a long streak combined with high activity, or if explicitly hinted at (though not available in current input). Avoid specific weight/rep advice.
5.  Keep the tone positive and motivating.
6.  Do not ask questions. Provide a direct tip.
7.  If there's very little data (e.g., no recent logs, zero streaks), provide a general motivational message like "Log your next workout to start tracking progress!" or "Consistency is key, let's get started!".

Example Output:
{
  "tip": "Amazing consistency with a {{streakData.current}}-day streak! Keep that momentum going this week."
}
{
  "tip": "Looks like you missed a few sessions recently. Try scheduling your workouts to stay on track!"
}
{
  "tip": "No recent workouts logged. Let's get back into it! Even a short session helps build momentum."
}

Output only the JSON object containing the tip.
`,
});

const coachingTipsFlow = ai.defineFlow(
  {
    name: 'coachingTipsFlow',
    inputSchema: CoachingTipsInputSchema,
    outputSchema: CoachingTipsOutputSchema,
  },
  async input => {
    // Basic validation or filtering can happen here if needed
    if (!input.recentLogs) {
        input.recentLogs = [];
    }
    if (!input.streakData) {
        input.streakData = { current: 0, longest: 0 };
    }

    const {output} = await prompt(input);
    if (!output) {
        // Fallback tip if AI fails
        return { tip: "Keep logging your workouts consistently to track your progress!" };
    }
    return output;
  }
);
