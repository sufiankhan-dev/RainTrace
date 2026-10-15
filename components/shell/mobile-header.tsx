"use client"

import { useState } from "react"
import { usePathname } from "next/navigation"
import { Menu } from "lucide-react"

import { Button } from "@/components/ui/button"
import {
  Sheet,
  SheetContent,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from "@/components/ui/sheet"
import { Badge } from "@/components/ui/badge"
import { Brand } from "@/components/shell/app-sidebar"
import { NavLink } from "@/components/shell/nav-link"
import { isActivePath, navItems } from "@/components/shell/nav-items"

export function MobileHeader() {
  const [open, setOpen] = useState(false)
  const pathname = usePathname()
  const current = navItems.find((item) => isActivePath(pathname, item.href))

  return (
    <header className="sticky top-0 z-40 flex h-14 items-center gap-3 border-b bg-background px-4 md:hidden">
      <Sheet open={open} onOpenChange={setOpen}>
        <SheetTrigger
          render={
            <Button variant="ghost" size="icon" aria-label="Open navigation" />
          }
        >
          <Menu aria-hidden="true" />
        </SheetTrigger>
        <SheetContent side="left" className="flex w-72 p-0 sm:max-w-xs">
          <SheetHeader className="border-b">
            <SheetTitle className="sr-only">Navigation</SheetTitle>
            <Brand onNavigate={() => setOpen(false)} />
          </SheetHeader>
          <nav
            aria-label="Primary"
            className="flex flex-1 flex-col gap-1 overflow-y-auto p-3"
          >
            {navItems.map((item) => (
              <NavLink
                key={item.href}
                item={item}
                onNavigate={() => setOpen(false)}
              />
            ))}
          </nav>
          <div className="flex flex-col gap-2 border-t p-3">
            <Badge variant="secondary" className="w-fit">
              Demo workspace
            </Badge>
            <p className="text-xs text-muted-foreground">
              Sample shell only — data, AI, and reports are not connected yet.
            </p>
          </div>
        </SheetContent>
      </Sheet>
      <div className="min-w-0 flex-1">
        <p className="truncate font-heading text-sm font-semibold tracking-tight">
          {current?.label ?? "RainTrace"}
        </p>
      </div>
    </header>
  )
}
