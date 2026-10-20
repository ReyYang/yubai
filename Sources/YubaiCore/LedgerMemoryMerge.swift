import Foundation

public enum LedgerMemoryMerge {
    public static func merge(chosen: Ledger, others: [Ledger]) -> Ledger {
        var result = chosen
        var areas = chosen.profile.generous.map { ($0, ProfileStance.generous) } + chosen.profile.restrain.map { ($0, ProfileStance.restrain) }
        let chosenAreaIDs = Set(areas.map { $0.0.id })
        var principles = chosen.profile.principles
        var dates = chosen.profile.principleDates
        for other in others where other.id == chosen.id {
            let incoming = other.profile.generous.map { ($0, ProfileStance.generous) } + other.profile.restrain.map { ($0, ProfileStance.restrain) }
            for (area, stance) in incoming {
                if !chosenAreaIDs.contains(area.id), chosen.profile.updatedAt >= (area.confirmedAt ?? other.profile.updatedAt) { continue }
                if let i = areas.firstIndex(where: { $0.0.id == area.id }) {
                    if (area.confirmedAt ?? .distantPast) > (areas[i].0.confirmedAt ?? .distantPast) { areas[i] = (area, stance) }
                } else { areas.append((area, stance)) }
            }
            for text in other.profile.principles {
                let incomingDate = other.profile.principleDates[text]
                if !chosen.profile.principles.contains(text), chosen.profile.updatedAt >= (incomingDate ?? other.profile.updatedAt) { continue }
                if !principles.contains(text) { principles.append(text) }
                if let incomingDate, incomingDate > (dates[text] ?? .distantPast) { dates[text] = incomingDate }
            }
            for card in other.cards {
                guard let i = result.cards.firstIndex(where: { $0.id == card.id }) else { result.cards.append(card); continue }
                var merged = result.cards[i]
                if let feedback = card.feedback {
                    let incomingDate = card.feedbackAt ?? card.createdAt
                    if merged.feedback == nil || incomingDate < (merged.feedbackAt ?? merged.createdAt) {
                        merged.feedback = feedback; merged.feedbackAt = incomingDate
                    }
                }
                if let dismissed = card.dismissedAt, dismissed < (merged.dismissedAt ?? .distantFuture) { merged.dismissedAt = dismissed }
                if merged.feedbackProposalID == nil { merged.feedbackProposalID = card.feedbackProposalID }
                if merged.areaID == nil { merged.areaID = card.areaID }
                result.cards[i] = merged
            }
            for topic in other.mutedTopics where !result.mutedTopics.contains(topic) { result.mutedTopics.append(topic) }
            for (key, category) in other.categoryMemory where result.categoryMemory[key] == nil { result.categoryMemory[key] = category }
        }
        result.profile.generous = areas.filter { $0.1 == .generous }.map { $0.0 }
        result.profile.restrain = areas.filter { $0.1 == .restrain }.map { $0.0 }
        result.profile.principles = principles; result.profile.principleDates = dates
        if result.profile != chosen.profile {
            result.profile.updatedAt = others.filter { $0.id == chosen.id }.reduce(chosen.profile.updatedAt) { max($0, $1.profile.updatedAt) }
        }
        return result
    }
}
