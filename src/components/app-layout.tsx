
// src/components/app-layout.tsx
'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { CalendarCheck, Dumbbell, PanelLeft, TrendingUp, LayoutGrid, LogOut } from 'lucide-react';
import {
  Sidebar,
  SidebarHeader,
  SidebarContent,
  SidebarMenu,
  SidebarMenuItem,
  SidebarMenuButton,
  SidebarFooter,
  SidebarInset,
  SidebarTrigger,
  useSidebar,
} from '@/components/ui/sidebar';
import { Button } from '@/components/ui/button';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Logo } from '@/components/icons/logo';
import { Separator } from '@/components/ui/separator';
import { useAuth } from '@/context/auth-context';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { getAllUserWorkoutPlans, initializeDefaultPlansForUser } from '@/lib/firestore-workout-plan-service';

const todayNavItem = {
  href: '/dashboard/today',
  icon: CalendarCheck,
  label: "Today's Session",
  subLabel: 'Log your current workout',
};

const mainDashboardNavItems = [
  {
    href: '/dashboard/progressive-overload',
    icon: TrendingUp,
    label: 'Progress Dashboard',
    subLabel: 'Track your gains',
  },
  {
    href: '/workout-plan', 
    icon: LayoutGrid,
    label: 'Full Workout Plan',
    subLabel: 'View all days',
  }
];

// Loading skeleton for when auth state is being determined
function AuthLoadingSkeleton() {
  return (
    <div className="flex h-screen w-full items-center justify-center bg-background">
      <div className="flex flex-col items-center gap-4">
        <Dumbbell className="h-12 w-12 animate-pulse text-primary" />
        <p className="text-muted-foreground">Initializing session...</p>
      </div>
    </div>
  );
}

// Layout for unauthenticated pages like login/signup
function PublicLayout({ children }: { children: React.ReactNode }) {
  return (
    <main className="flex h-screen flex-col items-center justify-center bg-background p-4">
      {children}
    </main>
  );
}

// Full app layout for authenticated users
function AuthenticatedLayout({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const { isMobile, setOpenMobile } = useSidebar();
  const { user, logout } = useAuth();
  const router = useRouter();

  const handleLinkClick = () => {
    if (isMobile) {
      setOpenMobile(false);
    }
  };

  const handleLogout = async () => {
    await logout();
    router.push('/login');
  };

  return (
     <>
      <Sidebar variant="sidebar" collapsible="icon">
        <SidebarHeader className="p-4">
            <div className="flex items-center gap-3">
              <Logo />
              <h1 className="text-2xl font-semibold text-sidebar-foreground group-data-[collapsible=icon]:hidden">
                GymTrack
              </h1>
            </div>
        </SidebarHeader>
        <Separator className="bg-sidebar-border group-data-[collapsible=icon]:hidden" />
        <SidebarContent asChild>
          <ScrollArea className="h-full">
            <SidebarMenu className="p-2 lg:p-4">
              <SidebarMenuItem key={todayNavItem.href}>
                <SidebarMenuButton
                  asChild
                  isActive={pathname === todayNavItem.href}
                  variant="default"
                  size="lg"
                  className="justify-start"
                  tooltip={todayNavItem.label}
                >
                  <Link href={todayNavItem.href} onClick={handleLinkClick}>
                    <todayNavItem.icon />
                    <div className="flex flex-col items-start">
                      <span>{todayNavItem.label}</span>
                      {todayNavItem.subLabel && <span className="text-xs text-sidebar-foreground/70 group-data-[collapsible=icon]:hidden">{todayNavItem.subLabel}</span>}
                    </div>
                  </Link>
                </SidebarMenuButton>
              </SidebarMenuItem>
            </SidebarMenu>

            <Separator className="my-2 bg-sidebar-border group-data-[collapsible=icon]:hidden" />

            {mainDashboardNavItems.length > 0 && (
              <SidebarMenu className="p-2 lg:p-4">
                {mainDashboardNavItems.map((item) => (
                  <SidebarMenuItem key={item.href}>
                    <SidebarMenuButton
                      asChild
                      isActive={pathname === item.href || pathname.startsWith(item.href + '/')}
                      variant="default"
                      size="lg"
                      className="justify-start"
                      tooltip={item.label}
                    >
                      <Link href={item.href} onClick={handleLinkClick}>
                        <item.icon />
                        <div className="flex flex-col items-start">
                          <span>{item.label}</span>
                          {item.subLabel && <span className="text-xs text-sidebar-foreground/70 group-data-[collapsible=icon]:hidden">{item.subLabel}</span>}
                        </div>
                      </Link>
                    </SidebarMenuButton>
                  </SidebarMenuItem>
                ))}
              </SidebarMenu>
            )}
            
          </ScrollArea>
        </SidebarContent>
        <SidebarFooter className="p-4">
          <SidebarMenuButton
            variant="default"
            size="default"
            className="justify-start"
            tooltip="Logout"
            onClick={handleLogout}
          >
            <LogOut />
            <span>Logout</span>
          </SidebarMenuButton>
          <p className="text-xs text-sidebar-foreground/50 px-2 pt-2 truncate group-data-[collapsible=icon]:hidden">
            {user?.email}
          </p>
        </SidebarFooter>
      </Sidebar>
      <SidebarInset className="flex flex-col">
        <header className="sticky top-0 z-10 flex h-14 items-center gap-4 border-b bg-background/80 px-4 backdrop-blur-sm sm:h-16 sm:px-6 md:hidden">
          <SidebarTrigger asChild>
            <Button size="icon" variant="outline">
              <PanelLeft />
              <span className="sr-only">Toggle Menu</span>
            </Button>
          </SidebarTrigger>
          <div className="flex items-center gap-2">
            <Dumbbell className="h-6 w-6 text-primary" />
            <h1 className="text-lg font-semibold">GymTrack</h1>
          </div>
        </header>
        <main className="flex-1 overflow-y-auto p-4 sm:p-6 md:p-8 bg-background text-foreground">
          {children}
        </main>
      </SidebarInset>
    </>
  );
}

export default function AppLayout({ children }: { children: React.ReactNode }) {
  const { user, loading: isAuthLoading } = useAuth();
  const queryClient = useQueryClient();
  const pathname = usePathname();
  const router = useRouter();

  const publicRoutes = ['/login', '/signup'];
  const onboardingRoutes = ['/onboarding/welcome', '/onboarding/choose-plan'];
  const isPublicRoute = publicRoutes.includes(pathname);
  const isOnboardingRoute = onboardingRoutes.includes(pathname);

  const { data: allPlans, isLoading: isLoadingPlans } = useQuery({
    queryKey: ['workoutPlans'],
    queryFn: () => {
      console.log(`[AppLayout] Querying workout plans for user: ${user?.uid || 'none'}`);
      return getAllUserWorkoutPlans();
    },
    enabled: true, 
  });

  useEffect(() => {
    console.log('[AppLayout EFFECT] Running effect, dependencies changed.');

    // This check is now safer. `allPlans` can be undefined, so we check for its existence first.
    const hasPlans = allPlans && allPlans.length > 0; 
    const hasActivePlan = allPlans?.some(p => p.isActive);

    console.table({
        pathname,
        isAuthLoading,
        isUserPresent: !!user,
        isLoadingPlans,
        isPublicRoute,
        isOnboardingRoute,
        hasPlans: hasPlans,
        hasActivePlan: hasActivePlan,
    });

    if (isAuthLoading) {
      console.log('[AppLayout EFFECT] Auth is loading. No action taken.');
      return;
    }

    if (!user) {
      if (!isPublicRoute) {
        console.log('[AppLayout EFFECT] No user, not on public route. Redirecting to /login.');
        router.replace('/login');
      } else {
        console.log('[AppLayout EFFECT] No user, on public route. Permitting access.');
      }
      return;
    }
    
    // User is logged in from here on.
    if (isLoadingPlans) {
       console.log('[AppLayout EFFECT] User is logged in, but plans are loading. Waiting.');
       return;
    }

    if (isOnboardingRoute) {
        console.log('[AppLayout EFFECT] On onboarding route. Permitting access regardless of plan status.');
        return;
    }

    // At this point, user is logged in, plans are loaded (or not), and not on an onboarding route.
    console.log(`[AppLayout EFFECT] Plan data loaded. Has active plan: ${hasActivePlan}`);
    if (!hasActivePlan) {
        console.log('[AppLayout EFFECT] No active plan found. Redirecting to /onboarding/welcome.');
        router.replace('/onboarding/welcome');
    } else if (isPublicRoute) {
         console.log('[AppLayout EFFECT] Has active plan, but on public route. Redirecting to /dashboard/today.');
        router.replace('/dashboard/today');
    } else {
        console.log('[AppLayout EFFECT] All conditions met, rendering page.');
    }
    
  }, [user, isAuthLoading, isLoadingPlans, allPlans, isPublicRoute, isOnboardingRoute, router, pathname]);
  
  // Determine what to render
  const isLoading = isAuthLoading || (!!user && isLoadingPlans && !isOnboardingRoute);
  
  if (isLoading) {
    console.log(`[AppLayout RENDER] Showing AuthLoadingSkeleton. isAuthLoading: ${isAuthLoading}, isLoadingPlans: ${isLoadingPlans}`);
    return <AuthLoadingSkeleton />;
  }

  if (user) {
      // After signup, `allPlans` might be null if they haven't been initialized yet.
      // The auth context handles initialization, but we wait here before deciding routes.
      if (allPlans === null && !isOnboardingRoute) {
         console.log('[AppLayout RENDER] User exists, but plans are null (pre-initialization). Showing loading skeleton.');
         return <AuthLoadingSkeleton />;
      }
      
      if (isOnboardingRoute) {
        console.log('[AppLayout RENDER] User is on onboarding route, rendering children.');
        return <>{children}</>;
      }

      // If they have an active plan, they are fully set up.
      if(allPlans?.some(p=>p.isActive)){
        console.log('[AppLayout RENDER] User is authenticated with active plan, showing AuthenticatedLayout.');
        return <AuthenticatedLayout>{children}</AuthenticatedLayout>;
      }

       console.log('[AppLayout RENDER] User authenticated, but no active plan state. Showing loading skeleton before redirect.');
       return <AuthLoadingSkeleton />;
  }
  
  if (!user && isPublicRoute) {
    console.log('[AppLayout RENDER] No user, showing PublicLayout.');
    return <PublicLayout>{children}</PublicLayout>;
  }
  
  console.log('[AppLayout RENDER] Fallback: Showing AuthLoadingSkeleton.');
  return <AuthLoadingSkeleton />;
}
