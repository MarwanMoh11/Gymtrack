
// src/components/dashboard/coaching-tip-card.tsx
'use client';

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button'; // Added Button import
import { Loader2, Lightbulb, RefreshCw } from 'lucide-react'; // Added RefreshCw

interface CoachingTipCardProps {
  tip: string | undefined | null;
  isLoading: boolean;
  onRefresh: () => void; // Callback to trigger fetching
}

export default function CoachingTipCard({ tip, isLoading, onRefresh }: CoachingTipCardProps) {
  return (
    <Card className="shadow-xl rounded-2xl">
      <CardHeader>
        <div className="flex justify-between items-center">
          <CardTitle className="text-xl font-bold text-primary flex items-center">
             <Lightbulb className="mr-2 h-5 w-5" />
             AI Coach Tip
          </CardTitle>
          {/* Refresh Button */}
          <Button
              variant="ghost"
              size="icon"
              onClick={onRefresh}
              disabled={isLoading}
              aria-label="Refresh coaching tip"
              className="text-primary hover:bg-primary/10"
           >
              <RefreshCw className={`h-4 w-4 ${isLoading ? 'animate-spin' : ''}`} />
          </Button>
        </div>
        <CardDescription>General advice based on your recent activity.</CardDescription>
      </CardHeader>
      <CardContent className="min-h-[150px] flex items-center justify-center">
        {isLoading && (
          <div className="flex flex-col items-center text-center py-8">
            <Loader2 className="h-8 w-8 animate-spin text-primary mb-3" />
            <span className="text-muted-foreground">Fetching coaching insights...</span>
          </div>
        )}
        {!isLoading && tip && ( // Display tip if available and not loading
          <blockquote className="text-center text-sm italic text-foreground/90 border-l-4 border-primary pl-4 py-2">
             "{tip}"
          </blockquote>
        )}
        {!isLoading && !tip && ( // Display initial prompt or fallback if no tip and not loading
           <div className="text-center py-8">
                <p className="text-muted-foreground">Click the refresh button <RefreshCw className="inline h-4 w-4 align-middle"/> to get your coaching tip.</p>
           </div>
        )}
      </CardContent>
    </Card>
  );
}

