function data()
    return {
    info = {
        name = _("Réseaux de communication"),
        description = _([[Ajoute des réseaux télécoms filaires et mobiles :
            - 1850 : Téléphone fixe (filaire) – croissance +
            - 1990 : 1er réseau mobile – croissance ++
            - 2020 : Fibre optique – croissance +++
            - 2030 : Réseaux mobiles modernes – croissance +++
            Couverture visible via deux calques (filaire & mobile).]]),
        minorVersion = 1,
        severityAdd = "NONE",
        severityRemove = "NONE",
        authors = { "elfloww" },
        tags = { "gameplay", "overlay", "city growth" },
        tfnetId = "com.elfloww.telecom_networks",
        },
        runFn = function() end,
    }
end