import {
  PageHeader,
  PlaceholderPanel,
} from "@/components/shell/page-header"

export default function OverviewPage() {
  return (
    <>
      <PageHeader
        title="Overview"
        description="Workspace summary and recent inspection activity."
      />
      <PlaceholderPanel feature="Workspace overview" />
    </>
  )
}
