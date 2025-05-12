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
import { summarizeRecentLogs } from '@/lib/workout-utils'; // Import utility

const LogSummarySchema = z.object({
  date: z.string().describe('Date of the workout (YYYY-MM-DD).'),
  exercisesCompleted: z.number().describe('Number of distinct exercises logged with at least one completed set on this day.'),
  setsCompleted: z.number().describe('Total number of sets marked as completed on this day.'),
});

const CoachingTipsInputSchema = z.object({
  recentLogs: z.array(LogSummarySchema).describe('A summary of workout logs from the last 2-4 weeks. Includes dates where logging occurred, even if 0 sets were marked complete.'),
  streakData: z.object({
    current: z.number().describe('Current workout streak in days (based on days with completed sets).'),
    longest: z.number().describe('Longest workout streak achieved in days (based on days with completed sets).'),
  }).describe('User\'s current and longest workout streaks.'),
  userGoal: z.string().optional().default('General strength and hypertrophy with progressive overload.').describe('The user\'s primary training goal.'),
});
export type CoachingTipsInput = z.infer<typeof CoachingTipsInputSchema>;

const CoachingTipsOutputSchema = z.object({
  tip: z.string().describe('A concise, actionable coaching tip based on recent activity and goals. Should be encouraging and offer general advice like considering deloads, intensity changes, or praising consistency. Should always provide a tip, even if data is minimal.'),
});
export type CoachingTipsOutput = z.infer<typeof CoachingTipsOutputSchema>;

// Updated wrapper function: fetches logs internally and removes pre-filtering
export async function getCoachingTip(streakData: { current: number; longest: number }, userGoal?: string): Promise<CoachingTipsOutput> {
  const recentLogs = summarizeRecentLogs(); // Fetch summarized logs

  const inputToSend: CoachingTipsInput = {
    recentLogs: recentLogs, // Pass all summarized logs, including those with 0 completed sets
    streakData: streakData,
    userGoal: userGoal || 'General strength and hypertrophy with progressive overload.', // Use provided or default goal
  };

  return coachingTipsFlow(inputToSend);
}


const prompt = ai.definePrompt({
  name: 'coachingTipsPrompt',
  input: {schema: CoachingTipsInputSchema},
  output: {schema: CoachingTipsOutputSchema},
  prompt: `You are an encouraging and insightful personal training AI coach. Analyze the user's recent workout activity and streaks to provide a helpful, general coaching tip. The user's goal is '{{{userGoal}}}'.

Workout Streaks (based on days with completed sets):
- Current: {{{streakData.current}}} days
- Longest: {{{streakData.longest}}} days

Recent Workout Summary (last 2-4 weeks - includes days where logging started but maybe nothing completed):
{{#if recentLogs.length}}
{{#each recentLogs}}
- Date: {{{date}}}, Exercises Completed: {{{exercisesCompleted}}}, Sets Completed: {{{setsCompleted}}}
{{/each}}
{{else}}
- No workouts logged recently.
{{/if}}

Based on this information:
1.  Acknowledge their consistency or lack thereof, using the streak data and log frequency/completion. Logs with 0 completed sets indicate an attempt was made but maybe not finished or fully logged.
2.  Look for patterns: Are they consistently logging workouts (even incomplete ones)? Are the number of *completed* sets/exercises consistent when they *do* complete workouts?
3.  Provide *one* concise, actionable, and encouraging coaching tip. **Always provide a tip.**
4.  Tips should be *general* guidance. Examples:
    - If consistency is good (high streak, frequent logs with completed sets): Praise it, suggest maintaining focus or considering a small intensity increase if appropriate.
    - If consistency is poor (low/zero streak, infrequent logs): Encourage getting back on track, suggest starting small, maybe logging just one exercise.
    - If logs show frequent attempts but low completion (0 completed sets often): "Good effort showing up! Focus on completing just a few key sets next time." or "Try reducing the number of exercises slightly to ensure completion."
    - If logs show activity but streaks are low: Maybe suggest scheduling workouts.
    - Consider suggesting a deload *only if* there's a long streak combined with high activity. Avoid specific weight/rep advice.
5.  Keep the tone positive and motivating.
6.  Do not ask questions. Provide a direct tip.
7.  If there's very little data (e.g., no recent logs, zero streaks): Provide a general motivational message like "Log your next workout to start tracking progress!" or "Let's get started! Log even one set today to build momentum.".

Example Output:
{
  "tip": "Amazing consistency with a {{streakData.current}}-day streak! Keep that momentum going this week."
}
{
  "tip": "Great job logging your workouts consistently! Remember to mark sets as complete to track your progress accurately."
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
    // Basic validation or normalization can happen here if needed
    if (!input.recentLogs) {
        input.recentLogs = [];
    }
    if (!input.streakData) {
        input.streakData = { current: 0, longest: 0 };
    }

    const {output} = await prompt(input);
    if (!output || !output.tip) {
        // Fallback tip if AI fails or returns empty tip
        console.error("AI failed to generate a valid tip, providing fallback.");
        return { tip: "Keep logging your workouts consistently to track your progress!" };
    }
    return output;
  }
);
