// CloudLibraryCatalogFixtures.swift
// Defines cloud library catalog fixtures for the Previews / PreviewFixtures surface.
//

import Foundation
import StratixCore
import StratixModels
import XCloudAPI

enum CloudLibraryCatalogFixtures {
    static let capturedCatalog: [CapturedCloudItem] = [
        .init(
            titleId: "TUNIC",
            productId: "9NLRT31Z4RWM",
            name: "TUNIC",
            publisher: "Finji",
            shortDescription: "Explore a land filled with lost legends, ancient powers, and ferocious monsters in this isometric adventure.",
            artURL: "https://store-images.s-microsoft.com/image/apps.5223.13702044937897358.8701ab78-da18-4c36-8c1e-3d4e6dfd60c9.31c8ed6f-acf1-4cf2-9863-640fe319abc3",
            posterURL: "https://store-images.s-microsoft.com/image/apps.11433.13702044937897358.8701ab78-da18-4c36-8c1e-3d4e6dfd60c9.be460380-78ee-493d-999d-f5943ba38e7a",
            heroURL: "https://store-images.s-microsoft.com/image/apps.34105.13702044937897358.8701ab78-da18-4c36-8c1e-3d4e6dfd60c9.86f47a6b-716e-40fa-aa62-61bf6f6e102c",
            attributes: ["4K Ultra HD", "Optimized for Xbox Series X|S", "Xbox achievements"],
            isInMRU: true
        ),
        .init(
            titleId: "ASPHALT9LEGENDS",
            productId: "9NZQPT0MWTD0",
            name: "Asphalt Legends",
            publisher: "Gameloft",
            shortDescription: "Arcade racing built around online competition, stunts, and fast hypercars.",
            artURL: "https://store-images.s-microsoft.com/image/apps.38333.14471421918435459.4ecc5a88-024b-4bd3-9a1a-e59259309560.3d2dcdb4-5eeb-4a98-bc8c-8afda4aa3f29",
            posterURL: "https://store-images.s-microsoft.com/image/apps.9713.14471421918435459.4ecc5a88-024b-4bd3-9a1a-e59259309560.6a126f98-ccef-4fd9-bd6f-b7f3b50049d9",
            heroURL: "https://store-images.s-microsoft.com/image/apps.64984.14471421918435459.50c2f163-8ffd-4c66-984a-186281ff7346.fd7c2a28-ee63-4686-9870-f74f5898380c",
            attributes: ["Online multiplayer (2-8)", "4K Ultra HD", "Single player"],
            isInMRU: true
        ),
        .init(
            titleId: "ANNO117PAXROMANA",
            productId: "9NRJ3KNT0JRK",
            name: "Anno 117: Pax Romana",
            publisher: "Ubisoft",
            shortDescription: "Build cities and govern your provinces while shaping the Roman Empire.",
            artURL: "https://store-images.s-microsoft.com/image/apps.61564.14382645289717684.af608e74-81a6-4af2-9362-0b74ef3f00e3.bf92f1a8-2226-4269-a424-6563c94525ef",
            posterURL: "https://store-images.s-microsoft.com/image/apps.5444.14382645289717684.af608e74-81a6-4af2-9362-0b74ef3f00e3.526673a0-93ef-4e2b-94cd-d19e72aaaff8",
            heroURL: "https://store-images.s-microsoft.com/image/apps.49133.14382645289717684.af608e74-81a6-4af2-9362-0b74ef3f00e3.ec2bbe4a-4923-4abb-9506-29af17550a5b",
            attributes: ["Online co-op (2-4)", "4K Ultra HD", "HDR10"],
            isInMRU: true
        ),
        .init(
            titleId: "POWERWASHSIMULATOR",
            productId: "9NHDJC0NW20M",
            name: "PowerWash Simulator",
            publisher: "Square Enix Ltd.",
            shortDescription: "A calm cleanup sim focused on pressure-washing maps solo or in co-op.",
            artURL: "https://store-images.s-microsoft.com/image/apps.60360.13631853399995812.7c8d5b79-31b8-46af-9143-329dfb697258.813651fd-f64f-4d40-a513-0584c3e6d6a5",
            posterURL: "https://store-images.s-microsoft.com/image/apps.61268.13631853399995812.7c8d5b79-31b8-46af-9143-329dfb697258.e21937ee-bfbb-4fa6-aea9-fc940c02feba",
            heroURL: "https://store-images.s-microsoft.com/image/apps.42503.13631853399995812.7c8d5b79-31b8-46af-9143-329dfb697258.5f06d2e9-fb6d-4e93-8ad0-f271312d6941",
            attributes: ["Online co-op (2-6)", "4K Ultra HD", "HDR10"],
            isInMRU: true
        ),
        .init(
            titleId: "ASTRONEER",
            productId: "9NBLGGH43KZB",
            name: "ASTRONEER",
            publisher: "System Era Softworks",
            shortDescription: "Terraform planets, discover resources, and survive in a colorful sci-fi sandbox.",
            artURL: "https://store-images.s-microsoft.com/image/apps.64849.13510798887933723.57e43f19-4066-429e-b1a2-caea56e427b4.860c35a4-ccbf-413e-9574-1c7c8826d6c6",
            posterURL: "https://store-images.s-microsoft.com/image/apps.17703.13510798887933723.57e43f19-4066-429e-b1a2-caea56e427b4.f555e1de-d116-4ab1-bed1-408a78622ba6",
            heroURL: "https://store-images.s-microsoft.com/image/apps.29512.13510798887933723.2e918b0b-2171-4602-baa4-ab1677624f25.465577c8-a626-4bf3-b4a1-19911855c773",
            attributes: ["Online co-op (2-4)", "Single player", "Xbox cloud saves"],
            isInMRU: true
        ),
        .init(
            titleId: "BATMANARKHAMKNIGHT",
            productId: "BSLX1RNXR6H7",
            name: "Batman™: Arkham Knight",
            publisher: "Warner Bros. Games",
            shortDescription: "The finale to Rocksteady's Arkham trilogy in Gotham under full siege.",
            artURL: "https://store-images.s-microsoft.com/image/apps.50680.69836087516172366.d802940c-fd8a-4174-8a68-e41a2475e1a1.efa1f648-fb98-4078-80cf-06f47811b1fa",
            posterURL: "https://store-images.s-microsoft.com/image/apps.27638.69836087516172366.d802940c-fd8a-4174-8a68-e41a2475e1a1.f1f791fa-f0bf-4e6a-8e7d-98f86a97b5a1",
            heroURL: "https://store-images.s-microsoft.com/image/apps.30637.69836087516172366.d802940c-fd8a-4174-8a68-e41a2475e1a1.77b11b55-654c-4be3-8804-09728b3a6901",
            attributes: ["Single player", "Cloud", "Action"],
            isInMRU: true
        ),
        .init(
            titleId: "AMONGUS",
            productId: "9NG07QJNK38J",
            name: "Among Us",
            publisher: "Innersloth",
            shortDescription: "A social deduction party game for teamwork, deception, and short rounds.",
            artURL: "https://store-images.s-microsoft.com/image/apps.21162.13589262686196899.16e3418a-cbf2-4748-9724-1c9dc9b7a0b9.14afafe9-1b03-4df0-95ad-12e2712a3b53",
            posterURL: "https://store-images.s-microsoft.com/image/apps.30063.13589262686196899.16e3418a-cbf2-4748-9724-1c9dc9b7a0b9.672da915-9117-4230-960d-4f59f3d7beb5",
            heroURL: "https://store-images.s-microsoft.com/image/apps.14626.13589262686196899.12354b81-d410-4255-b6aa-9f9a68a694ae.dec2ecaf-85b7-4792-b5aa-13c1a3b31c5e",
            attributes: ["Online co-op (4-15)", "Online multiplayer (4-15)", "4K Ultra HD"],
            isInMRU: false
        ),
        .init(
            titleId: "BRAWLHALLA",
            productId: "C3B1V55CDL0C",
            name: "Brawlhalla",
            publisher: "Ubisoft",
            shortDescription: "Free-to-play platform fighter with local and online multiplayer support.",
            artURL: "https://store-images.s-microsoft.com/image/apps.45185.65958767407690020.477d935e-dd77-4870-a3aa-fc59fa179e40.cbaf79ff-1abb-49d8-b41b-5ddc834ace7b",
            posterURL: "https://store-images.s-microsoft.com/image/apps.37719.65958767407690020.477d935e-dd77-4870-a3aa-fc59fa179e40.0ffa386d-2d1c-4786-8045-6f0913f9d56f",
            heroURL: "https://store-images.s-microsoft.com/image/apps.39724.13891464908023063.a041e1c7-f56f-4ac1-ab92-18f9ca74105a.08fa5ea8-3157-4314-8e90-04ff3dce38ed",
            attributes: ["Xbox local co-op (2-4)", "Online co-op (2-4)", "Online multiplayer"],
            isInMRU: false
        ),
        .init(
            titleId: "CALLOFDUTYHQ",
            productId: "9N201KQXS5BM",
            name: "Call of Duty®",
            publisher: "Activision Publishing Inc.",
            shortDescription: "Unified Call of Duty hub including Black Ops and Warzone content.",
            artURL: "https://store-images.s-microsoft.com/image/apps.13837.13966330883349940.11992bbd-8e09-48bd-a61d-26246908b0e0.1e64d977-2eba-49c2-b904-3b47b4805d73",
            posterURL: "https://store-images.s-microsoft.com/image/apps.42015.13966330883349940.e8d96f51-63dc-4377-8441-88d85afdd80a.d84cbd17-ae03-4537-8641-8c33c308de78",
            heroURL: "https://store-images.s-microsoft.com/image/apps.57334.13966330883349940.04429733-dfe9-4aac-bee6-505b6bbb4f65.91a803a2-f429-4cce-9bc9-85e6ea0aa601",
            attributes: ["Online multiplayer (2-64)", "4K Ultra HD", "Optimized for Xbox Series X|S"],
            isInMRU: false
        ),
        .init(
            titleId: "CELESTE",
            productId: "BWMQL2RPWBHB",
            name: "Celeste",
            publisher: "Matt Makes Games Inc.",
            shortDescription: "Precision platforming across handcrafted challenges and story-rich mountain climbs.",
            artURL: "https://store-images.s-microsoft.com/image/apps.7117.71633162879241707.7cf18b3b-9fa5-486f-9a68-067f06d50bf1.3bb742ae-b2ed-4066-bf27-ea50d614ce8c",
            posterURL: "https://store-images.s-microsoft.com/image/apps.21257.71633162879241707.7cf18b3b-9fa5-486f-9a68-067f06d50bf1.8f7909cf-d9a5-44aa-9901-2635255ab2ee",
            heroURL: "https://store-images.s-microsoft.com/image/apps.24023.71633162879241707.7cf18b3b-9fa5-486f-9a68-067f06d50bf1.6778804d-f496-4d2c-87db-8df1ec5beda7",
            attributes: ["Single player", "Xbox achievements", "Xbox cloud saves"],
            isInMRU: false
        ),
        .init(
            titleId: "CHIVALRY2",
            productId: "9N7CJX93ZGWN",
            name: "Chivalry 2",
            publisher: "Tripwire Interactive LLC",
            shortDescription: "Large-scale medieval battles with melee combat focused on multiplayer chaos.",
            artURL: "https://store-images.s-microsoft.com/image/apps.51715.14071745200459129.f6415fab-b460-4210-a974-f5c4ed9bcf0e.1e14dfd5-c275-43ec-8fe1-033a88f883e0",
            posterURL: "https://store-images.s-microsoft.com/image/apps.20769.14071745200459129.f6415fab-b460-4210-a974-f5c4ed9bcf0e.d40e2d3f-9fc3-49bb-bd15-44aa422c8c8e",
            heroURL: "https://store-images.s-microsoft.com/image/apps.2651.14071745200459129.f6415fab-b460-4210-a974-f5c4ed9bcf0e.73cdb7e3-f838-4633-b998-4a3083fc6e9a",
            attributes: ["Online multiplayer (2-64)", "4K Ultra HD", "Optimized for Xbox Series X|S"],
            isInMRU: false
        ),
        .init(
            titleId: "CITIESSKYLINESREMASTERED",
            productId: "9MZ4GBWX9GND",
            name: "Cities: Skylines - Remastered",
            publisher: "Paradox Interactive",
            shortDescription: "City-building sim remastered for modern Xbox hardware.",
            artURL: "https://store-images.s-microsoft.com/image/apps.29080.13877341660077011.7198ab78-e545-4cfe-8105-110d8c697dac.0e9d3b1f-ac49-4095-aff8-1907560d4d18",
            posterURL: "https://store-images.s-microsoft.com/image/apps.41631.13877341660077011.7198ab78-e545-4cfe-8105-110d8c697dac.7f82efb8-521a-4424-89b3-3d8c14075fcc",
            heroURL: "https://store-images.s-microsoft.com/image/apps.44327.13877341660077011.7198ab78-e545-4cfe-8105-110d8c697dac.d2ceb53d-787a-4398-aedf-c9612ecd6352",
            attributes: ["Single player", "Controller", "City Builder"],
            isInMRU: false
        ),
        .init(
            titleId: "CITIESSKYLINESMAYORSEDITION",
            productId: "C4GH8N6ZXG5L",
            name: "Cities: Skylines - Xbox One Edition",
            publisher: "Paradox Interactive",
            shortDescription: "Build and manage a city from its first streets to a sprawling metropolis.",
            artURL: "https://store-images.s-microsoft.com/image/apps.42716.66617542682682743.811213f2-2c45-4145-973d-fe3e3774b196.c2dab488-7382-45d1-bf6c-6b8be6e3fd96",
            posterURL: "https://store-images.s-microsoft.com/image/apps.7220.66617542682682743.811213f2-2c45-4145-973d-fe3e3774b196.96b48a30-7ed1-4bc9-8f8b-b114375b2e1c",
            heroURL: "https://store-images.s-microsoft.com/image/apps.59972.66617542682682743.811213f2-2c45-4145-973d-fe3e3774b196.2eb7da78-667d-41a9-b63f-f3f7a8d077c7",
            attributes: ["Single player", "4K Ultra HD", "Xbox achievements"],
            isInMRU: false
        ),
        .init(
            titleId: "CONTROL",
            productId: "BZ6W9LRPC26W",
            name: "Control",
            publisher: "505 Games",
            shortDescription: "Supernatural action-adventure centered on powers, weapons, and shifting environments.",
            artURL: "https://store-images.s-microsoft.com/image/apps.12883.64090029807136264.88ddb0db-cfad-423c-bb52-c5b649930fb1.d18863ca-36c5-49ab-9877-af99ddf348e5",
            posterURL: "https://store-images.s-microsoft.com/image/apps.48174.64090029807136264.88ddb0db-cfad-423c-bb52-c5b649930fb1.18259e82-3a13-4440-ae66-031e2e818198",
            heroURL: "https://store-images.s-microsoft.com/image/apps.32013.64090029807136264.88ddb0db-cfad-423c-bb52-c5b649930fb1.26ba6d14-3c7a-4d96-b3ba-7df17ae976c8",
            attributes: ["Single player", "Xbox achievements", "Xbox cloud saves"],
            isInMRU: false
        )
    ]
}

struct CapturedCloudItem {
    let titleId: String
    let productId: String
    let name: String
    let publisher: String
    let shortDescription: String
    let artURL: String
    let posterURL: String
    let heroURL: String
    let attributes: [String]
    let isInMRU: Bool

    var asCloudLibraryItem: CloudLibraryItem {
        CloudLibraryItem(
            titleId: titleId,
            productId: productId,
            name: name,
            shortDescription: shortDescription,
            artURL: URL(string: artURL),
            posterImageURL: URL(string: posterURL),
            heroImageURL: URL(string: heroURL),
            publisherName: publisher,
            attributes: attributes.map { CloudLibraryAttribute(name: $0, localizedName: $0) },
            supportedInputTypes: ["Controller"],
            isInMRU: isInMRU
        )
    }
}
