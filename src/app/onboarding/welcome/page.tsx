// src/app/onboarding/welcome/page.tsx
import Link from 'next/link';
import { Card, CardHeader, CardTitle, CardDescription, CardContent, CardFooter } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Dumbbell, ArrowRight } from 'lucide-react';

export default function WelcomePage() {
  return (
    <div className="flex items-center justify-center min-h-screen bg-background">
      <Card className="max-w-lg w-full shadow-2xl">
        <CardHeader className="text-center">
          <Dumbbell className="mx-auto h-12 w-12 text-primary" />
          <CardTitle className="text-3xl font-bold mt-4">Welcome to GymTrack!</CardTitle>
          <CardDescription className="text-lg text-muted-foreground mt-2">
            Let's set up your first workout plan.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <p className="text-center text-foreground/80">
            You can start with one of our expertly-designed default plans or build your own from scratch.
          </p>
        </CardContent>
        <CardFooter className="flex flex-col sm:flex-row gap-4 p-6">
          <Button asChild size="lg" className="w-full">
            <Link href="/onboarding/choose-plan">
              Choose a Pre-built Plan
              <ArrowRight className="ml-2 h-4 w-4" />
            </Link>
          </Button>
          <Button asChild size="lg" variant="outline" className="w-full">
            <Link href="/onboarding/create-plan">
              Build My Own Plan
            </Link>
          </Button>
        </CardFooter>
      </Card>
    </div>
  );
}
