export type PublicLeaderboardRow = {
  nickname: string;
  attended_count: number;
  late_count: number;
  no_show_count: number;
  activity_points: number;
};

function toInteger(value: unknown): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.trunc(parsed) : 0;
}

/**
 * Build the only data shape allowed to leave the public leaderboard endpoint.
 * Excludes user identifiers and all profile data while preserving the public attendance counters.
 */
export function buildPublicLeaderboard(
  sourceRows: readonly Record<string, unknown>[],
) {
  const rows: PublicLeaderboardRow[] = sourceRows.map((row) => {
    const rawNickname = typeof row.nickname === "string"
      ? row.nickname.trim()
      : "";
    return {
      nickname: rawNickname || "會員",
      attended_count: toInteger(row.attended_count),
      late_count: toInteger(row.late_count),
      no_show_count: toInteger(row.no_show_count),
      activity_points: toInteger(row.activity_points),
    };
  });

  return {
    rows,
    summary: {
      total_members: rows.length,
      total_attended: rows.reduce((sum, row) => sum + row.attended_count, 0),
      total_activity_points: rows.reduce(
        (sum, row) => sum + row.activity_points,
        0,
      ),
    },
  };
}
