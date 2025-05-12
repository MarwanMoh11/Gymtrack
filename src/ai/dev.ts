import { config } from 'dotenv';
config();

import '@/ai/flows/adjust-weight-recommendation.ts';
import '@/ai/flows/next-session-recommendation.ts';
import '@/ai/flows/coaching-tips-flow.ts'; // Add import for the new flow
