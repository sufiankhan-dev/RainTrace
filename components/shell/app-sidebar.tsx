"use client"

import Link from "next/link"
import { Droplets } from "lucide-react"

import { Badge } from "@/components/ui/badge"
import { Separator } from "@/components/ui/separator"
import { NavLink } from "@/components/shell/nav-link"
import { navItems } from "@/components/shell/nav-items"

export function Brand({ onNavigate }: { onNavigate?: () => void }) {
  return (
    <Link
      href="/"
      onClick={onNavigate}
      className="flex items-center gap-2.5 rounded-lg px-3 py-2 outline-none focus-visible:ring-3 focus-visible:ring-ring/50"
    >
      <span className="flex size-8 shrink-0 items-center justify-center rounded-lg bg-primary text-primary-foreground">
        <Droplets className="size-4" aria-hidden="true" />
      </span>
      <span className="flex min-w-0 flex-col">
        <span className="truncate font-heading text-sm font-semibold tracking-tight">
          RainTrace
        </span>
        <span className="truncate text-[0.7rem] text-muted-foreground">
          Inspection workspace
        </span>
      </span>
    </Link>
  )
}

export function AppSidebar() {
  return (
    <div className="flex h-full flex-col gap-4">
      <div className="px-1">
        <Brand />
      </div>
      <Separator />
      <nav aria-label="Primary" className="flex flex-1 flex-col gap-1 px-3">
        {navItems.map((item) => (
          <NavLink key={item.href} item={item} />
        ))}
      </nav>
      <Separator />
      <div className="flex flex-col gap-2 px-3 pb-1">
        <Badge variant="secondary" className="w-fit">
          Demo workspace
        </Badge>
        <p className="px-0.5 text-xs text-muted-foreground">
          Sample shell only — data, AI, and reports are not connected yet.
        </p>
      </div>
    </div>
  )
}
