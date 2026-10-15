import { AppSidebar } from "@/components/shell/app-sidebar"
import { MobileHeader } from "@/components/shell/mobile-header"

export function AppShell({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-svh w-full bg-muted/30">
      <aside
        aria-label="Sidebar"
        className="sticky top-0 hidden h-svh w-64 shrink-0 border-r bg-sidebar p-4 text-sidebar-foreground md:block"
      >
        <AppSidebar />
      </aside>
      <div className="flex min-w-0 flex-1 flex-col">
        <MobileHeader />
        <main className="flex-1 px-4 py-6 md:px-8 md:py-8">
          <div className="mx-auto w-full max-w-5xl">{children}</div>
        </main>
      </div>
    </div>
  )
}
