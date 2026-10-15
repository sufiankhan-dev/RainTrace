import {
  PageHeader,
  PlaceholderPanel,
} from "@/components/shell/page-header"

export default function ReportsPage() {
  return (
    <>
      <PageHeader
        title="Reports"
        description="Generate and share inspection reports with your team."
      />
      <PlaceholderPanel feature="Report generator" />
    </>
  )
}
