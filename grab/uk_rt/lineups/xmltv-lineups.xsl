<?xml version="1.0" encoding="ISO-8859-1"?>
<xsl:stylesheet version="1.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform">

<xsl:template match="/">
<html>
    <body>
        <h2>Master Lineup for <xsl:value-of select="xmltv-lineups/xmltv-lineup/display-name"/></h2>
            <table border="1">
                <tr bgcolor="#9acd32">
                    <th>Preset</th>
                    <th>Icon</th>
                    <th>Name</th>
                </tr>
                <xsl:for-each select="xmltv-lineups/xmltv-lineup/lineup-entry">
                <tr>
                    <td><xsl:value-of select="preset"/></td>
                    <xsl:choose>
                        <xsl:when test="station/logo">
                                <td><img src="{station/logo/@url}" width="66" height="50"/></td>
                        </xsl:when>
                        <xsl:otherwise>
                            <td></td>
                        </xsl:otherwise>
                    </xsl:choose>
                    <xsl:choose>
                        <xsl:when test="station[@rfc2838]">
                            <td bgcolor="lime"><xsl:value-of select="station/name"/></td>
                        </xsl:when>
                        <xsl:otherwise>
                            <td bgcolor="red"><xsl:value-of select="station/name"/></td>
                        </xsl:otherwise>
                    </xsl:choose>
                </tr>
                </xsl:for-each>
            </table>
    </body>
</html>
</xsl:template>

</xsl:stylesheet>
