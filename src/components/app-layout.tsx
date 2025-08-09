// src/components/app-layout.tsx
'use client';

import { useEffect } from 'react';
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
import { useQuery } from '@tanstack/react-query';
import { getUserData } from '@/lib/firestore-workout-plan-service';

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
  const pathname = usePathname();
  const router = useRouter();

  const publicRoutes = ['/login', '/signup'];
  const onboardingRoutes = ['/onboarding/welcome', '/onboarding/choose-plan', '/onboarding/create-plan', '/onboarding/create-plan/configure-days', '/workout-plan'];
  const isPublicRoute = publicRoutes.includes(pathname);
  const isOnboardingRoute = onboardingRoutes.some(route => pathname.startsWith(route));

  const { data: userData, isLoading: isLoadingUserData } = useQuery({
    queryKey: ['userData', user?.uid],
    queryFn: () => getUserData(user!.uid),
    enabled: !!user,
  });

  useEffect(() => {
    if (isAuthLoading) {
      return; 
    }

    if (!user) {
      if (!isPublicRoute) {
        router.replace('/login');
      }
      return;
    }

    if (isLoadingUserData) {
        return;
    }
    
    // Once user and their data are loaded, perform routing logic.
    if (userData) {
        if (userData.onboardingStatus === 'needs_plan_selection') {
            if (!isOnboardingRoute) {
                router.replace('/onboarding/welcome');
            }
        } else if (userData.onboardingStatus === 'completed') {
            if (isPublicRoute || (isOnboardingRoute && pathname !== '/workout-plan')) {
                router.replace('/dashboard/today');
            }
        }
    } else if (!isPublicRoute) {
        // This case can happen if the user doc creation is delayed.
        // It's safer to redirect to login if no user data is found for a logged-in user on a protected route.
        // The AuthContext also tries to initialize data, so this is a fallback.
        router.replace('/login');
    }

  }, [user, userData, isAuthLoading, isLoadingUserData, pathname, isPublicRoute, isOnboardingRoute, router]);
  
  // --- Render Logic ---
  const isLoading = isAuthLoading || (!!user && isLoadingUserData);
  
  if (isLoading) {
    return <AuthLoadingSkeleton />;
  }

  if (user && userData) {
     if (userData.onboardingStatus === 'needs_plan_selection') {
         // Allow rendering onboarding routes if user needs it
         return isOnboardingRoute ? <>{children}</> : <AuthLoadingSkeleton />;
     }
     if (userData.onboardingStatus === 'completed') {
        // If onboarding is done, show authenticated layout unless on a public/onboarding route (redirect is pending)
        return (isPublicRoute || (isOnboardingRoute && pathname !== '/workout-plan')) 
            ? <AuthLoadingSkeleton /> 
            : <AuthenticatedLayout>{children}</AuthenticatedLayout>;
     }
  }
  
  // If no user, only render public routes.
  if (!user && isPublicRoute) {
    return <PublicLayout>{children}</PublicLayout>;
  }

  // Fallback for any other edge cases during transitions.
  return <AuthLoadingSkeleton />;
}
