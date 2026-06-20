/*
 * This file is part of the AzerothCore Project. See AUTHORS file for Copyright information
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
 * more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program. If not, see <http://www.gnu.org/licenses/>.
 */

#ifndef APPENDERFILE_H
#define APPENDERFILE_H

#include "Appender.h"
#include <atomic> // NOTE: this import is NEEDED (even though some IDEs report it as unused)
#include <vector>

class AppenderFile : public Appender
{
public:
    static constexpr AppenderType type = APPENDER_FILE;

    AppenderFile(uint8 id, std::string const& name, LogLevel level, AppenderFlags flags, std::vector<std::string_view> const& args);
    ~AppenderFile();
    FILE* OpenFile(std::string const& name, std::string const& mode, bool backup);
    std::string BuildDateFileName(std::string const& baseName, std::string const& date) const;
    AppenderType getType() const override { return type; }

private:
    void CloseFile();
    void _write(LogMessage const* message) override;
    FILE* logfile;
    std::string _fileName;
    std::string _baseFileName;
    std::string _currentDate;
    std::string _logDir;
    bool _dynamicName;
    bool _backup;
    bool _useDate;
    uint64 _maxFileSize;
    std::atomic<uint64> _fileSize;
};

#endif
