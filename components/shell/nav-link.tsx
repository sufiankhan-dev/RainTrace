"use client"

import Link from "next/link"
import { usePathname } from "next/navigation"
import { cn } from "cn"

import { isActivePath, type NavItem } from "@/components/shell/nav-items"

type NavLinkProps = {
  item: NavItem
  onNavigate?: () => void
}

export function NavLink({ item, onNavigate }: NavLinkProps) {
  const pathname = usePathname()
  const active = isActivePath(pathname, item.href)
  const Icon = item.icon

  return (
    <Link
      href={item.href}
      onClick={onNavigate}
      aria-current={active ? "page" : undefined}
      className={cn(
        "group flex items-center gap-3 rounded-lg px-3 py-2 text-sm font-medium outline-none transition-colors focus-visible:ring-3 focus-visible:ring-ring/50",
        active
          ? "bg-sidebar-primary text-sidebar-primary-foreground"
          : "text-muted-foreground hover:bg-sidebar-accent hover:text-sidebar-accent-foreground"
      )}
    >
      <Icon
        className={cn(
          "size-4 shrink-0",
          active ? "text-sidebar-primary-foreground" : "text-muted-foreground"
        )}
        aria-hidden="true"
      />
      <span className="truncate">{item.label}</span>
    </Link>
  )
}
